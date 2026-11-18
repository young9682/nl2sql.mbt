///|
fn fixture() -> String {
  @env.get_env_var("NL2SQL_FIXTURE").unwrap_or(
    "../../sqlite/fixtures/orders.db",
  )
}

///|
test "inventory report reads typed data through the public dependency" {
  let result = low_stock(fixture(), 10L)
  assert_eq(result.columns, ["region", "title", "available"])
  assert_eq(result.rows, [[Text("east"), Text("Tea"), Integer(5L)]])
  assert_false(result.truncated)
}

///|
test "inventory report labels a limited result as partial" {
  let result = low_stock(fixture(), 20L, max_rows=1)
  let report = report_json(result)
  assert_true(
    report
    is {
      "status": "partial",
      "inventory": {
        "rows": [[["Text", "east"], ["Text", "Tea"], ["Integer", "5"]]],
        "truncated": true,
        ..
      },
      ..
    },
  )
}

///|
test "public query policy rejects writes even when called from this module" {
  let path = fixture()
  let expected = low_stock(path, 20L)
  let denied = try {
    ignore(@sqlite.query(path, "DELETE FROM stock"))
    false
  } catch {
    @sqlite.QueryError::Rejected(_) => true
    error => raise error
  }
  assert_true(denied)
  assert_eq(low_stock(path, 20L).rows, expected.rows)
}
