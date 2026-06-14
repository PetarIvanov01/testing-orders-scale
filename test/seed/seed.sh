#!/usr/bin/env bash
set -euo pipefail

customer_count="${CUSTOMER_COUNT:-10000}"
min_orders="${MIN_ORDERS:-5}"
max_orders="${MAX_ORDERS:-10}"
min_items="${MIN_ITEMS:-2}"
max_items="${MAX_ITEMS:-5}"
batch_size="${BATCH_SIZE:-100}"
product_count="${PRODUCT_COUNT:-100000}"

psql_base=(psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB")

echo "Seeding customer analytics dataset"
echo "customers=${customer_count} orders/customer=${min_orders}-${max_orders} items/order=${min_items}-${max_items} batch=${batch_size}"

"${psql_base[@]}" <<SQL
TRUNCATE TABLE order_line_items, orders, customers RESTART IDENTITY CASCADE;

CREATE UNLOGGED TABLE IF NOT EXISTS seed_products (
  id BIGINT PRIMARY KEY,
  base_price NUMERIC(14, 2) NOT NULL
);

TRUNCATE TABLE seed_products;

INSERT INTO seed_products (id, base_price)
SELECT
  product_id,
  round((5 + random() * 495)::numeric, 2)
FROM generate_series(1, ${product_count}) AS product_id;
SQL

batch_start=1

while [ "$batch_start" -le "$customer_count" ]; do
  batch_end=$((batch_start + batch_size - 1))
  if [ "$batch_end" -gt "$customer_count" ]; then
    batch_end="$customer_count"
  fi

  echo "Seeding customers ${batch_start} through ${batch_end}"

  "${psql_base[@]}" <<SQL
INSERT INTO customers (id, email, total_spent, orders_count, last_order_at, created_at)
SELECT
  customer_id,
  'customer.' || customer_id || '@' ||
    (ARRAY['gmail.com', 'outlook.com', 'icloud.com', 'yahoo.com', 'example-shop.test'])[1 + floor(random() * 5)::int],
  0,
  0,
  NULL,
  now() - ((30 + random() * 1795)::int || ' days')::interval
FROM generate_series(${batch_start}, ${batch_end}) AS customer_id;

INSERT INTO orders (customer_id, status, processed_at, created_at)
SELECT
  c.id,
  order_status.status,
  CASE
    WHEN order_status.status = 'pending' THEN NULL
    ELSE order_created.created_at + ((1 + random() * 96)::int || ' hours')::interval
  END,
  order_created.created_at
FROM customers AS c
CROSS JOIN LATERAL generate_series(
  1,
  ${min_orders} + floor(random() * (${max_orders} - ${min_orders} + 1) + c.id * 0)::int
) AS order_number
CROSS JOIN LATERAL (
  SELECT random() + c.id * 0 + order_number * 0 AS roll
) AS status_roll
CROSS JOIN LATERAL (
  SELECT
    CASE
      WHEN status_roll.roll < 0.82 THEN 'completed'
      WHEN status_roll.roll < 0.90 THEN 'cancelled'
      WHEN status_roll.roll < 0.96 THEN 'refunded'
      ELSE 'pending'
    END AS status
) AS order_status
CROSS JOIN LATERAL (
  SELECT GREATEST(
    c.created_at,
    now() - (((random() + c.id * 0 + order_number * 0) * 1095)::int || ' days')::interval
  ) AS created_at
) AS order_created
WHERE c.id BETWEEN ${batch_start} AND ${batch_end};

INSERT INTO order_line_items (order_id, product_id, quantity, unit_price)
SELECT
  o.id,
  product_sample.product_id,
  quantity_sample.quantity,
  round((p.base_price * (0.85 + random() * 0.45))::numeric, 2)
FROM orders AS o
CROSS JOIN LATERAL generate_series(
  1,
  ${min_items} + floor(random() * (${max_items} - ${min_items} + 1) + o.id * 0)::int
) AS line_number
CROSS JOIN LATERAL (
  SELECT 1 + floor((random() + o.id * 0 + line_number * 0) * ${product_count})::bigint AS product_id
) AS product_sample
JOIN seed_products AS p ON p.id = product_sample.product_id
CROSS JOIN LATERAL (
  SELECT random() + o.id * 0 + line_number * 0 AS roll
) AS quantity_roll
CROSS JOIN LATERAL (
  SELECT
    CASE
      WHEN quantity_roll.roll < 0.72 THEN 1
      WHEN quantity_roll.roll < 0.92 THEN 2
      WHEN quantity_roll.roll < 0.98 THEN 3
      ELSE 4 + floor(random() * 7)::int
    END AS quantity
) AS quantity_sample
WHERE o.customer_id BETWEEN ${batch_start} AND ${batch_end};
SQL

  batch_start=$((batch_end + 1))
done

"${psql_base[@]}" <<SQL
SELECT
  (SELECT COUNT(*) FROM customers) AS customers,
  (SELECT COUNT(*) FROM orders) AS orders,
  (SELECT COUNT(*) FROM order_line_items) AS order_line_items;
SQL
