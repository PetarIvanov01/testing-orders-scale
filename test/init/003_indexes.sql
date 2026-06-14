CREATE INDEX IF NOT EXISTS idx_orders_completed_period_customer
  ON orders (processed_at, customer_id)
  WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_orders_customer_completed_processed
  ON orders (customer_id, processed_at DESC)
  WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id
  ON order_line_items (order_id);

ANALYZE customers;
ANALYZE orders;
ANALYZE order_line_items;
