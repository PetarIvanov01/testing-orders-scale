# Customer Analytics Test Harness

This folder contains the runnable Postgres/pgAdmin environment, seed profile,
and Knex-based recalculation implementation for testing the pseudo-code from
the root `index.ts`.

## Setup

Run commands from this folder:

```bash
cd test
npm install
```

## Environment Files

Seed and Docker init config lives in `.env.seed`:

```env
SEED_ON_INIT=true
CUSTOMER_COUNT=100000
MIN_ORDERS=10
MAX_ORDERS=10
MIN_ITEMS=3
MAX_ITEMS=5
BATCH_SIZE=10000
PRODUCT_COUNT=100000
```

This creates approximately:

- 100,000 customers
- 1,000,000 orders
- 3,000,000-5,000,000 order line items

Recalculation job config lives in `.env.recalculate`:

```env
PGHOST=localhost
PGPORT=5432
PGDATABASE=customer_analytics
PGUSER=app
PGPASSWORD=app_password
PGPOOL_MAX=10

FROM_DATE=2000-01-01T00:00:00.000Z
TO_DATE=2100-01-01T00:00:00.000Z
BATCH_SIZE=1000
RECALCULATION_CONCURRENCY=8
```

## Docker

Start Postgres and pgAdmin:

```bash
npm run docker:up
```

Stop containers without deleting data:

```bash
npm run docker:down
```

Reset the database volume and seed from scratch:

```bash
npm run seed
```

`npm run seed` is an alias for `npm run docker:reset`. Postgres only runs init
scripts when the database volume is empty, so reseeding requires deleting the
volume.

Follow Postgres logs while seeding:

```bash
npm run docker:logs
```

Check row counts:

```bash
npm run db:counts
```

## Connections

Postgres:

- Host: `localhost`
- Port: `5432`
- Database: `customer_analytics`
- User: `app`
- Password: `app_password`

pgAdmin:

- URL: `http://localhost:5050`
- Email: `admin@example.com`
- Password: `admin_password`

Inside pgAdmin, the registered server is `Customer Analytics Postgres`.
When prompted for the server password, use `app_password`.

## Recalculation

Run the customer analytics recalculation job:

```bash
npm run recalculate
```

The script loads `.env.recalculate` through Node's native `--env-file` flag.

Run TypeScript checks:

```bash
npm run typecheck
```
