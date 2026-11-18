///|
let fixture = "sqlite/fixtures/orders.db"

///|
fn query_error(
  run : () -> @sqlite.QueryResult raise @sqlite.QueryError,
) -> @sqlite.QueryError? {
  ignore(run()) catch {
    error => return Some(error)
  }
  None
}

///|
test "read ordered and typed rows from a SQLite file with bound parameters" {
  let result = @sqlite.query(
    fixture,
    "SELECT orders.id, users.name, amount, note, receipt FROM orders JOIN users ON users.id = orders.user_id WHERE orders.id = ?",
    params=[Integer(9007199254740993L)],
  )
  assert_eq(result.columns, ["id", "name", "amount", "note", "receipt"])
  assert_eq(result.rows, [
    [Integer(9007199254740993L), Text("林"), Real(42.5), Null, Blob(b"")],
  ])
  assert_false(result.truncated)
}

///|
test "bind all SQLite storage classes and preserve empty text and binary data" {
  let params : Array[@sqlite.Value] = [
    Null,
    Integer(-9223372036854775808L),
    Real(1.25),
    Text(""),
    Text("a\u{0}b"),
    Blob(b"\x01\x00\xff"),
  ]
  let result = @sqlite.query(fixture, "SELECT ?, ?, ?, ?, ?, ?", params~)
  assert_eq(result.rows, [params])
}

///|
test "CTEs work and SQLite ignores trailing comments and empty delimiters" {
  let result = @sqlite.query(
    fixture,
    "WITH totals AS (SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id) SELECT total FROM totals WHERE user_id = ?; -- ignore ;\n ;",
    params=[Integer(1L)],
  )
  assert_eq(result.rows, [[Real(50.0)]])
  let literal = @sqlite.query(fixture, "SELECT 'a;b';")
  assert_eq(literal.rows, [[Text("a;b")]])
}

///|
test "denied writes and connection operations leave the fixture unchanged" {
  let statements = [
    "DELETE FROM orders", "WITH ids AS (SELECT id FROM orders) UPDATE orders SET amount = 0 WHERE id IN (SELECT id FROM ids) RETURNING id",
    "CREATE TEMP TABLE tmp(id)", "ATTACH DATABASE ':memory:' AS other", "PRAGMA user_version = 3",
  ]
  let snapshot = "SELECT id, user_id, amount, note, receipt FROM orders ORDER BY id"
  let before = @sqlite.query(fixture, snapshot)
  for sql in statements {
    let error = query_error(() => @sqlite.query(fixture, sql))
    assert_true(error is Some(@sqlite.QueryError::Rejected(_)), msg=sql)
  }
  let load_error = query_error(() => {
    @sqlite.query(fixture, "SELECT load_extension('not-loaded')")
  })
  // Some SQLite builds omit the extension-loading function entirely.
  assert_true(
    load_error
    is Some(
      @sqlite.QueryError::Rejected(_)
      | @sqlite.QueryError::SqliteError(1, _)
    ),
  )
  let after = @sqlite.query(fixture, snapshot)
  assert_eq(after.rows, before.rows)
}

///|
test "only a single complete query is accepted" {
  let empty = query_error(() => @sqlite.query(fixture, " ; -- comment\n ; "))
  assert_true(empty is Some(@sqlite.QueryError::EmptyStatement))
  let multiple = query_error(() => {
    @sqlite.query(fixture, "SELECT 1; /* comment */ SELECT 2")
  })
  assert_true(multiple is Some(@sqlite.QueryError::MultipleStatements))
  let trailing_write = query_error(() => {
    @sqlite.query(fixture, "SELECT 1; DELETE FROM orders")
  })
  assert_true(trailing_write is Some(@sqlite.QueryError::MultipleStatements))
  let malformed = query_error(() => @sqlite.query(fixture, "SELECT FROM orders"))
  assert_true(malformed is Some(@sqlite.QueryError::SqliteError(_, _)))
  let embedded_nul = query_error(() => {
    @sqlite.query(fixture, "SELECT 1\u{0}; SELECT 2")
  })
  assert_true(embedded_nul is Some(@sqlite.QueryError::InvalidInput(_)))
  let oversized_sql = "SELECT 1; -- " + "x".repeat(64 * 1024)
  let oversized = query_error(() => @sqlite.query(fixture, oversized_sql))
  assert_true(oversized is Some(@sqlite.QueryError::InvalidInput(_)))
}

///|
test "invalid arguments and missing database files return structured errors" {
  let fewer = query_error(() => {
    @sqlite.query(fixture, "SELECT ?, ?", params=[Null])
  })
  assert_true(fewer is Some(@sqlite.QueryError::ParameterCount(2, 1)))
  let more = query_error(() => @sqlite.query(fixture, "SELECT 1", params=[Null]))
  assert_true(more is Some(@sqlite.QueryError::ParameterCount(0, 1)))
  let missing = query_error(() => {
    @sqlite.query("sqlite/fixtures/missing.db", "SELECT 1")
  })
  assert_true(missing is Some(@sqlite.QueryError::OpenFailed(_, _)))
  let unbounded = query_error(() => {
    @sqlite.query(fixture, "SELECT 1", max_rows=0)
  })
  assert_true(unbounded is Some(@sqlite.QueryError::InvalidInput(_)))
}

///|
test "empty results and an exact row limit are distinct from truncation" {
  let sql = "SELECT id FROM orders ORDER BY id"
  let empty = @sqlite.query(fixture, "SELECT id FROM orders WHERE 0")
  assert_eq(empty.columns, ["id"])
  assert_eq(empty.rows, [])
  assert_false(empty.truncated)
  let exact = @sqlite.query(fixture, sql, max_rows=3)
  assert_eq(exact.rows.length(), 3)
  assert_false(exact.truncated)
  let limited = @sqlite.query(fixture, sql, max_rows=2)
  assert_eq(limited.rows, [[Integer(1L)], [Integer(2L)]])
  assert_true(limited.truncated)
}

///|
test "timeout interrupts work and later queries can open the fixture" {
  let timed_out = query_error(() => {
    @sqlite.query(
      fixture,
      "WITH RECURSIVE counter(i) AS (VALUES(1) UNION ALL SELECT i + 1 FROM counter WHERE i < 1000000000) SELECT sum(i) FROM counter",
      timeout_ms=10,
    )
  })
  assert_true(timed_out is Some(@sqlite.QueryError::TimedOut))
  let result = @sqlite.query(fixture, "SELECT count(*) FROM orders")
  assert_eq(result.rows, [[Integer(3L)]])
}
