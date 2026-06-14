import { Knex } from "knex";

interface QueryOptions {
  fromDate: Date;
  toDate: Date;
  cursor: number | null;
  limit: number;
}

interface CustomerAnalytics {
  customerId: number;
  totalSpent: string;
  ordersCount: number;
  lastOrderAt: string | null;
}

interface RecalculationResult {
  affectedCustomers: number;
  batches: number;
  concurrency: number;
  durationMs: number;
}

interface AnalyticsQueryRow {
  customerId: string | number;
  totalSpent: string | null;
  ordersCount: string | number;
  lastOrderAt: string | null;
}

class CustomerAnalyticsRecalculationJob {
  constructor(
    private readonly orderRepository: OrderRepository,
    private readonly customerRepository: CustomerRepository,
    private readonly batchSize = 1000,
    private readonly concurrency = 1
  ) {}

  async recalculate(
    fromDate: Date,
    toDate: Date
  ): Promise<RecalculationResult> {
    if (fromDate >= toDate) {
      throw new Error("fromDate must be before toDate");
    }

    const startedAt = Date.now();
    let cursor: number | null = null;
    let affectedCustomers = 0;
    const batches: number[][] = [];

    while (true) {
      const affectedCustomerIds =
        await this.orderRepository.findAffectedCustomerIds({
          fromDate,
          toDate,
          cursor,
          limit: this.batchSize
        });

      if (affectedCustomerIds.length === 0) {
        break;
      }

      affectedCustomers += affectedCustomerIds.length;
      batches.push(affectedCustomerIds);
      cursor = affectedCustomerIds.at(-1) ?? null;
    }

    await this.processBatches(batches);

    return {
      affectedCustomers,
      batches: batches.length,
      concurrency: this.concurrency,
      durationMs: Date.now() - startedAt
    };
  }

  private async processBatches(batches: number[][]): Promise<void> {
    let nextBatchIndex = 0;
    const processorCount = Math.min(this.concurrency, batches.length);

    const processors = Array.from({ length: processorCount }, async () => {
      while (nextBatchIndex < batches.length) {
        const batch = batches[nextBatchIndex];
        nextBatchIndex += 1;

        const analytics =
          await this.orderRepository.calculateAnalyticsForCustomers(batch);

        await this.customerRepository.updateAnalytics(analytics);
      }
    });

    await Promise.all(processors);
  }
}

class OrderRepository {
  constructor(private readonly db: Knex) {}

  async findAffectedCustomerIds({
    fromDate,
    toDate,
    cursor,
    limit
  }: QueryOptions): Promise<number[]> {
    const query = this.db("orders")
      .distinct("orders.customer_id")
      .where("orders.status", "completed")
      .where("orders.processed_at", ">=", fromDate)
      .where("orders.processed_at", "<", toDate)
      .orderBy("orders.customer_id", "asc")
      .limit(limit);

    if (cursor !== null) {
      query.where("orders.customer_id", ">", cursor);
    }

    const rows = await query;
    return rows.map((row) => Number(row.customer_id));
  }

  async calculateAnalyticsForCustomers(
    customerIds: number[]
  ): Promise<CustomerAnalytics[]> {
    if (customerIds.length === 0) {
      return [];
    }

    const rows = (await this.db("orders")
      .select({
        customerId: "orders.customer_id"
      })
      .select(this.db.raw('MAX(orders.processed_at)::text AS "lastOrderAt"'))
      .sum({
        totalSpent: this.db.raw(
          "order_line_items.quantity * order_line_items.unit_price"
        )
      })
      .countDistinct({
        ordersCount: "orders.id"
      })
      .join("order_line_items", "order_line_items.order_id", "orders.id")
      .where("orders.status", "completed")
      .whereIn("orders.customer_id", customerIds)
      .groupBy("orders.customer_id")) as AnalyticsQueryRow[];

    return rows.map((row) => ({
      customerId: Number(row.customerId),
      totalSpent: String(row.totalSpent ?? "0"),
      ordersCount: Number(row.ordersCount ?? 0),
      lastOrderAt: row.lastOrderAt
    }));
  }
}

class CustomerRepository {
  constructor(private readonly db: Knex) {}

  async updateAnalytics(analyticsRows: CustomerAnalytics[]): Promise<void> {
    if (analyticsRows.length === 0) {
      return;
    }

    await this.db.transaction(async (trx) => {
      const valuesSql = analyticsRows
        .map(() => "(?::bigint, ?::numeric, ?::integer, ?::timestamptz)")
        .join(", ");

      const bindings = analyticsRows.flatMap((row) => [
        row.customerId,
        row.totalSpent,
        row.ordersCount,
        row.lastOrderAt
      ]);

      await trx.raw(
        `
          UPDATE customers AS c
          SET
            total_spent = data.total_spent,
            orders_count = data.orders_count,
            last_order_at = data.last_order_at
          FROM (VALUES ${valuesSql}) AS data(
            customer_id,
            total_spent,
            orders_count,
            last_order_at
          )
          WHERE c.id = data.customer_id
        `,
        bindings
      );
    });
  }
}

export {
  CustomerAnalyticsRecalculationJob,
  CustomerRepository,
  OrderRepository
};
