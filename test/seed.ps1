$ErrorActionPreference = "Stop"

$CustomerCount = if ($env:CUSTOMER_COUNT) { [long]$env:CUSTOMER_COUNT } else { 10000 }
$MinOrders = if ($env:MIN_ORDERS) { [int]$env:MIN_ORDERS } else { 5 }
$MaxOrders = if ($env:MAX_ORDERS) { [int]$env:MAX_ORDERS } else { 10 }
$MinItems = if ($env:MIN_ITEMS) { [int]$env:MIN_ITEMS } else { 2 }
$MaxItems = if ($env:MAX_ITEMS) { [int]$env:MAX_ITEMS } else { 5 }
$BatchSize = if ($env:BATCH_SIZE) { [int]$env:BATCH_SIZE } else { 100 }
$ProductCount = if ($env:PRODUCT_COUNT) { [int]$env:PRODUCT_COUNT } else { 100000 }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$seedSql = Join-Path $scriptDir "seed\seed.sql"

if (-not (Test-Path $seedSql)) {
  throw "Seed SQL file not found: $seedSql"
}

$estimatedOrdersLow = $CustomerCount * [long]$MinOrders
$estimatedOrdersHigh = $CustomerCount * [long]$MaxOrders
$estimatedItemsLow = $estimatedOrdersLow * [long]$MinItems
$estimatedItemsHigh = $estimatedOrdersHigh * [long]$MaxItems

Write-Host "About to seed:"
Write-Host "  Customers:        $CustomerCount"
Write-Host "  Orders:           $estimatedOrdersLow - $estimatedOrdersHigh"
Write-Host "  Order line items: $estimatedItemsLow - $estimatedItemsHigh"
Write-Host ""
Write-Host "This is destructive: existing customers, orders, and order_line_items will be truncated."
Write-Host "The default profile is sized for 100,000 - 500,000 order line items."
Write-Host ""

if ($env:CONFIRM_FULL_SEED -ne "yes") {
  throw "Set CONFIRM_FULL_SEED=yes to run. For a smoke test, override CUSTOMER_COUNT/MIN_ORDERS/MAX_ORDERS/MIN_ITEMS/MAX_ITEMS with smaller values."
}

docker cp $seedSql customer-analytics-postgres:/tmp/seed.sql

docker exec customer-analytics-postgres psql `
  -U app `
  -d customer_analytics `
  -v customer_count=$CustomerCount `
  -v min_orders=$MinOrders `
  -v max_orders=$MaxOrders `
  -v min_items=$MinItems `
  -v max_items=$MaxItems `
  -v batch_size=$BatchSize `
  -v product_count=$ProductCount `
  -f /tmp/seed.sql
