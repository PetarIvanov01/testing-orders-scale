# Customer Analytics Recalculation Evaluation

## Current Dataset

The current Docker Postgres database was seeded from `.env.seed`:

Current row counts:

| Table            |      Rows |
| ---------------- | --------: |
| customers        |   100,000 |
| orders           | 1,000,000 |
| order_line_items | 4,000,131 |

Recalculation range:

```env
FROM_DATE=2000-01-01T00:00:00.000Z
TO_DATE=2100-01-01T00:00:00.000Z
PGPOOL_MAX=10
```

## Implementation Change

The original job processed batches serially:

1. Load one affected customer-id batch.
2. Aggregate analytics for that batch.
3. Update the corresponding customer rows.
4. Repeat.

The updated job first collects affected customer-id batches, then processes
those independent batches with bounded in-flight batch concurrency.

Current default:

```env
BATCH_SIZE=1000
RECALCULATION_CONCURRENCY=8
```

## Current Results

All runs below used the current 100,000-customer dataset and were run
sequentially, waiting for each test to finish before starting the next.

| Batch size | In-flight batches | Total batches |  Duration |
| ---------: | ----------------: | ------------: | --------: |
|        500 |                 1 |           200 | 20,873 ms |
|        500 |                 8 |           200 |  6,888 ms |
|      1,000 |                 1 |           100 | 11,241 ms |
|      1,000 |                 8 |           100 |  4,690 ms |
|      5,000 |                 1 |            20 | 10,922 ms |
|      5,000 |                 8 |            20 |  8,153 ms |
|     10,000 |                 2 |            10 |  5,432 ms |

Best observed stable setting:

```env
BATCH_SIZE=1000
RECALCULATION_CONCURRENCY=8
```

Latest best run:

```json
{
  "batchSize": 1000,
  "affectedCustomers": 100000,
  "batches": 100,
  "concurrency": 8,
  "durationMs": 4690
}
```

Compared with the same batch size at one in-flight batch, 8 in-flight batches
reduced runtime from 11,241 ms to 4,690 ms.

```text
(11241 - 4690) / 11241 = 58.3%
```

The fastest observed run in this pass was `BATCH_SIZE=1000` with
`RECALCULATION_CONCURRENCY=8`.

## Notes

`BATCH_SIZE=10000` with `RECALCULATION_CONCURRENCY=8` failed on the larger
dataset because Postgres could not resize a shared memory segment inside the
Docker container. Lower concurrency or smaller batches avoid that container
resource limit.

Very large update batches can also hit bind-parameter limits because the
current `UPDATE ... FROM (VALUES ...)` implementation uses four bind parameters
per updated customer row.

```

```
