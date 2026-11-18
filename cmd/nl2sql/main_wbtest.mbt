///|
async test "demo replays a question against SQLite and returns executed SQL and evidence" {
  let args = ["--demo"]
  let output = run(args[:])
  assert_true(
    output
    is {
      "status": "ok",
      "sql": String(sql),
      "result": {
        "rows": [
          [["Text", "林"], ["Real", 50]],
          [["Text", "Sam"], ["Real", 20]],
        ],
        ..
      },
      "context": {
        "schema": { "tables": [_, _, _, _], .. },
        "foreign_keys": [_, _],
        ..
      },
      ..
    } &&
    sql.contains("JOIN"),
  )
}

///|
async test "CLI distinguishes an empty query from an unanswerable question" {
  let empty_args = ["--demo", "empty-dataset-result"]
  let empty = run(empty_args[:])
  assert_true(empty is { "status": "empty", "result": { "rows": [], .. }, .. })
  let refusal_args = ["--demo", "unanswerable-profit"]
  let refusal = run(refusal_args[:])
  assert_true(
    refusal is { "status": "no_answer", "answer": String(reason), .. } &&
    !reason.is_empty(),
  )
}

///|
async test "CLI row limit reports truncation with retained evidence" {
  let args = ["--max-rows", "1", "--demo"]
  let outcome = run(args[:])
  assert_true(
    outcome
    is {
      "status": "truncated",
      "result": { "truncated": true, "rows": [_], .. },
      ..
    },
  )
}

///|
test "SQLite rejections, missing databases, and timeouts have distinct CLI statuses" {
  let fixture = "sqlite/fixtures/orders.db"
  assert_eq(
    query_failure(() => @sqlite.query(fixture, "DELETE FROM orders")),
    ("query_rejected", 1),
  )
  assert_eq(
    query_failure(() => @sqlite.query("sqlite/fixtures/missing.db", "SELECT 1")),
    ("database_error", 1),
  )
  assert_eq(
    query_failure(() => {
      @sqlite.query(
        fixture,
        "WITH RECURSIVE counter(i) AS (VALUES(1) UNION ALL SELECT i + 1 FROM counter WHERE i < 1000000000) SELECT sum(i) FROM counter",
        timeout_ms=10,
      )
    }),
    ("query_timeout", 1),
  )
}

///|
fn query_failure(
  query : () -> @sqlite.QueryResult raise @sqlite.QueryError,
) -> (String, Int32) raise {
  ignore(query()) catch {
    error => {
      let (status, _, code) = describe_error(error)
      return (status, code)
    }
  }
  fail("expected a SQLite query error")
}
