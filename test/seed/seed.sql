\set ON_ERROR_STOP on

\echo Seeding customer analytics dataset
\echo customers=:customer_count orders/customer=:min_orders-:max_orders items/order=:min_items-:max_items batch=:batch_size

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
FROM generate_series(1, :product_count) AS product_id;

CREATE OR REPLACE FUNCTION seed_customer_analytics_data(
  customer_count BIGINT,
  min_orders INTEGER,
  max_orders INTEGER,
  min_items INTEGER,
  max_items INTEGER,
  batch_size INTEGER,
  product_count INTEGER
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  batch_start BIGINT := 1;
  batch_end BIGINT;
BEGIN
  IF customer_count < 1 THEN
    RAISE EXCEPTION 'customer_count must be positive';
  END IF;

  IF min_orders < 1 OR max_orders < min_orders THEN
    RAISE EXCEPTION 'invalid order bounds: % - %', min_orders, max_orders;
  END IF;

  IF min_items < 1 OR max_items < min_items THEN
    RAISE EXCEPTION 'invalid item bounds: % - %', min_items, max_items;
  END IF;

  IF batch_size < 1 THEN
    RAISE EXCEPTION 'batch_size must be positive';
  END IF;

  WHILE batch_start <= customer_count LOOP
    batch_end := LEAST(batch_start + batch_size - 1, customer_count);
    RAISE NOTICE 'Seeding customers % through %', batch_start, batch_end;

    INSERT INTO customers (id, email, total_spent, orders_count, last_order_at, created_at)
    SELECT
      customer_id,
      'customer.' || customer_id || '@' ||
        (ARRAY['gmail.com', 'outlook.com', 'icloud.com', 'yahoo.com', 'example-shop.test'])[1 + floor(random() * 5)::int],
      0,
      0,
      NULL,
      now() - ((30 + random() * 1795)::int || ' days')::interval
    FROM generate_series(batch_start, batch_end) AS customer_id;

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
      min_orders + floor(random() * (max_orders - min_orders + 1) + c.id * 0)::int
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
    WHERE c.id BETWEEN batch_start AND batch_end;

    INSERT INTO order_line_items (order_id, product_id, quantity, unit_price)
    SELECT
      o.id,
      product_sample.product_id,
      quantity_sample.quantity,
      round((p.base_price * (0.85 + random() * 0.45))::numeric, 2)
    FROM orders AS o
    CROSS JOIN LATERAL generate_series(
      1,
      min_items + floor(random() * (max_items - min_items + 1) + o.id * 0)::int
    ) AS line_number
    CROSS JOIN LATERAL (
      SELECT 1 + floor((random() + o.id * 0 + line_number * 0) * product_count)::bigint AS product_id
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
    WHERE o.customer_id BETWEEN batch_start AND batch_end;

    batch_start := batch_end + 1;
  END LOOP;

  UPDATE customers AS c
  SET
    total_spent = COALESCE(a.total_spent, 0),
    orders_count = COALESCE(a.orders_count, 0),
    last_order_at = a.last_order_at
  FROM (
    SELECT
      o.customer_id,
      SUM(oli.quantity * oli.unit_price) AS total_spent,
      COUNT(DISTINCT o.id)::integer AS orders_count,
      MAX(o.processed_at) AS last_order_at
    FROM orders AS o
    JOIN order_line_items AS oli ON oli.order_id = o.id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
  ) AS a
  WHERE c.id = a.customer_id;

  ANALYZE customers;
  ANALYZE orders;
  ANALYZE order_line_items;
END;
$$;

SELECT seed_customer_analytics_data(
  :customer_count,
  :min_orders,
  :max_orders,
  :min_items,
  :max_items,
  :batch_size,
  :product_count
);

SELECT
  (SELECT COUNT(*) FROM customers) AS customers,
  (SELECT COUNT(*) FROM orders) AS orders,
  (SELECT COUNT(*) FROM order_line_items) AS order_line_items;
