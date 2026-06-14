import { createDb } from "./db";
import {
  CustomerAnalyticsRecalculationJob,
  CustomerRepository,
  OrderRepository
} from "./index";

function parseDate(value: string | undefined, fallback: Date): Date {
  if (!value) {
    return fallback;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid date: ${value}`);
  }

  return parsed;
}

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`Invalid positive integer: ${value}`);
  }

  return parsed;
}

async function main() {
  const db = createDb();

  try {
    const toDate = parseDate(process.env.TO_DATE, new Date());
    const fromDate = parseDate(
      process.env.FROM_DATE,
      new Date(toDate.getTime() - 365 * 24 * 60 * 60 * 1000)
    );
    const batchSize = parsePositiveInteger(process.env.BATCH_SIZE, 1000);
    const concurrency = parsePositiveInteger(
      process.env.RECALCULATION_CONCURRENCY,
      1
    );

    const job = new CustomerAnalyticsRecalculationJob(
      new OrderRepository(db),
      new CustomerRepository(db),
      batchSize,
      concurrency
    );

    const result = await job.recalculate(fromDate, toDate);

    console.log({
      fromDate: fromDate.toISOString(),
      toDate: toDate.toISOString(),
      batchSize,
      ...result
    });
  } finally {
    await db.destroy();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
