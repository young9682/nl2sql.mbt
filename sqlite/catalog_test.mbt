///|
test "read columns and foreign keys from the fixture without including views" {
  let catalog = @sqlite.read_catalog("sqlite/fixtures/orders.db")
  assert_eq(catalog.schema.tables.map(table => table.name), [
    "orders", "products", "stock", "users",
  ])
  guard catalog.schema.find_table("orders") is Some(orders) else {
    fail("orders is missing")
  }
  assert_eq(orders.columns.map(column => column.name), [
    "id", "user_id", "amount", "note", "receipt",
  ])
  assert_eq(orders.columns[2].col_type, "REAL")
  assert_false(orders.columns[2].nullable)
  assert_true(orders.columns[0].primary_key)
  assert_eq(catalog.foreign_keys.length(), 2)
  let orders_fk = catalog.foreign_keys[0]
  assert_eq(orders_fk.source_table, "orders")
  assert_eq(orders_fk.source_columns, ["user_id"])
  assert_eq(orders_fk.target_table, "users")
  assert_eq(orders_fk.target_columns, [Some("id")])
  let stock_fk = catalog.foreign_keys[1]
  assert_eq(stock_fk.source_table, "stock")
  assert_eq(stock_fk.source_columns, ["region", "sku"])
  assert_eq(stock_fk.target_table, "products")
  assert_eq(stock_fk.target_columns, [Some("region"), Some("sku")])
}
