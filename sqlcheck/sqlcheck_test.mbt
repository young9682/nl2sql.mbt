// Blackbox tests for the public API of `young9682/nl2sql/sqlcheck`.

///|
test "plain SELECT passes" {
  let check = @sqlcheck.check_read_only("SELECT id, email FROM users")
  assert_true(check.ok)
  assert_eq(check.statements, 1)
  assert_eq(check.reason, "")
}

///|
test "CTE SELECT passes" {
  let check = @sqlcheck.check_read_only(
    "WITH big AS (SELECT * FROM orders WHERE amount > 100) SELECT * FROM big",
  )
  assert_true(check.ok)
  assert_eq(check.statements, 1)
}

///|
test "multiple queries pass" {
  let check = @sqlcheck.check_read_only(
    "SELECT 1; SELECT 2; SELECT count(*) FROM users",
  )
  assert_true(check.ok)
  assert_eq(check.statements, 3)
}

///|
test "subqueries inside a query pass" {
  let check = @sqlcheck.check_read_only(
    "SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)",
  )
  assert_true(check.ok)
}

///|
test "semicolon inside a string literal does not split" {
  let check = @sqlcheck.check_read_only("SELECT 'a;b' FROM users")
  assert_true(check.ok)
  assert_eq(check.statements, 1)
}

///|
test "trailing semicolon is fine" {
  let check = @sqlcheck.check_read_only("SELECT 1;")
  assert_true(check.ok)
  assert_eq(check.statements, 1)
}

///|
test "DELETE is rejected at statement 1" {
  let check = @sqlcheck.check_read_only("DELETE FROM users")
  assert_true(!check.ok)
  assert_eq(check.statements, 1)
  assert_true(check.reason.contains("statement 1"))
}

///|
test "INSERT is rejected" {
  let check = @sqlcheck.check_read_only(
    "INSERT INTO users (email) VALUES ('a@b.c')",
  )
  assert_true(!check.ok)
}

///|
test "UPDATE is rejected" {
  let check = @sqlcheck.check_read_only("UPDATE users SET email = 'x'")
  assert_true(!check.ok)
}

///|
test "DROP TABLE is rejected" {
  let check = @sqlcheck.check_read_only("DROP TABLE orders")
  assert_true(!check.ok)
}

///|
test "CREATE TABLE is rejected" {
  let check = @sqlcheck.check_read_only("CREATE TABLE t (id INTEGER)")
  assert_true(!check.ok)
}

///|
test "a write statement among queries is rejected with its position" {
  let check = @sqlcheck.check_read_only("SELECT 1; DELETE FROM users")
  assert_true(!check.ok)
  assert_eq(check.statements, 2)
  assert_true(check.reason.contains("statement 2"))
}

///|
test "leading garbage identifier is rejected" {
  let check = @sqlcheck.check_read_only("SELEC * FRMO users")
  assert_true(!check.ok)
  assert_true(check.reason.contains("identifier"))
}

///|
test "empty scripts are rejected" {
  let empty = @sqlcheck.check_read_only("")
  assert_true(!empty.ok)
  assert_true(empty.reason != "")
}
