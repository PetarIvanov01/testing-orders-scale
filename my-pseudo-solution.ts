/*
# Customer Analytics Recalculation Job
## Context
You are working on an e-commerce platform. The system stores customers, orders, and order line items.
The platform has millions of orders.

We use JavaScript / Node.js and an ORM such as Sequelize, TypeORM, Prisma, or Objection.js.

## Database Schema

```sql
customers
- id
- email
- total_spent
- orders_count
- last_order_at
- created_at

orders
- id
- customer_id -> customers
- status
- processed_at
- created_at

order_line_items
- id
- order_id -> orders
- product_id
- quantity
- unit_price
```

```sql 

  SELECT * 
  FROM  orders 
  WHERE status = "completed" 
  AND created_at BETWEEN {fromDate} AND {toDate};

  SELECT
   o.id AS orderId,
   SUM(ol.quantity * ol.unit_price) AS totalSpent
  FROM orders AS o 
  JOIN order_line_items AS ol 
    ON ol.order_id = o.id 
  WHERE o.status = "completed"
   AND o.processed_at BETWEEN {fromDate} AND {toDate}
  Group BY o.id; -> Calculate the totalSpent per order

```

## Task

Implement a background service that recalculates customer analytics.

The service should expose the following method:
The method should find all customers that have orders in the given period and recalculate their analytics fields.
Save the results in the database

```js
totalSpent = sum of total_price of all completed orders []
ordersCount = count of all completed orders []
lastOrderAt = date of the latest completed order []
```

## Skeleton
*/
import { raw } from "orm";

interface QueryOptions {
  fromDate: Date;
  toDate: Date;
  cursor: number | null;
  limit: number;
}

class CustomerAnalyticsRecalculationJob {
  customerRepository: CustomerRepository;
  orderRepository: OrderRepository;
  batchSize: number;
  concurrency: number;
  constructor(
    orderRepository: OrderRepository,
    customerRepository: CustomerRepository,
    batchSize = 1000,
    concurrency = 8
  ) {
    this.orderRepository = orderRepository;
    this.customerRepository = customerRepository;
    this.batchSize = batchSize;
    this.concurrency = concurrency;
  }

  async recalculate(fromDate: any, toDate: any) {
    let cursor = null;
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

      batches.push(affectedCustomerIds);
      cursor = affectedCustomerIds.at(-1) ?? null;
    }

    await this.processBatches(batches);
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

/* order.service.ts */
class OrderRepository {
  orderModel: any;
  constructor(orderModel: any) {
    this.orderModel = orderModel;
  }
  async findAffectedCustomerIds({
    fromDate,
    toDate,
    cursor,
    limit
  }: QueryOptions): Promise<number[]> {
    let query = this.orderModel
      .query()
      .select("orders.customer_id")
      .where("orders.status", "completed")
      .where("orders.processed_at", ">=", fromDate)
      .where("orders.processed_at", "<", toDate)
      .groupBy("orders.customer_id")
      .orderBy("orders.customer_id", "asc")
      .limit(limit);

    if (cursor !== null) {
      query = query.where("orders.customer_id", ">", cursor);
    }

    return await query.run();
  }

  async calculateAnalyticsForCustomers(
    customerIds: number[]
  ): Promise<CustomerAnalytics[]> {
    return this.orderModel
      .query()
      .select({
        customerId: "orders.customer_id",
        totalSpent: raw(
          "SUM(order_line_items.quantity * order_line_items.unit_price)"
        ),
        ordersCount: raw("COUNT(DISTINCT orders.id)"),
        lastOrderAt: raw("MAX(orders.processed_at)")
      })
      .join("order_line_items", "order_line_items.order_id", "orders.id")
      .where("orders.status", "completed")
      .whereIn("orders.customer_id", customerIds)
      .groupBy("orders.customer_id")
      .run();
  }
}

/* customer.service.ts */
interface CustomerAnalytics {
  customerId: number;
  totalSpent: number;
  ordersCount: number;
  lastOrderAt: Date | null;
}

class CustomerRepository {
  customerModel: any;
  constructor(customerModel: any) {
    this.customerModel = customerModel;
  }

  async updateAnalytics(analyticsRows: CustomerAnalytics[]): Promise<void> {
    if (analyticsRows.length === 0) {
      return;
    }

    await this.customerModel
      .query()
      .insert(
      analyticsRows.map((analytics) => ({
        id: analytics.customerId,
        totalSpent: analytics.totalSpent,
        ordersCount: analytics.ordersCount,
        lastOrderAt: analytics.lastOrderAt
      }))
      )
      .onConflict("id")
      .merge(["totalSpent", "ordersCount", "lastOrderAt"]);
  }
}
