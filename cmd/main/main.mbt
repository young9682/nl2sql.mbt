///|
/// Demo: schema digest + DDL from M0, and the M1 read-only gate.
/// Run with `moon run cmd/main` from the project root.
fn main {
  let schema = @lib.sample_schema()
  println(schema.digest())
  println(schema.create_table_sql())
  println("")
  let samples = [
    "SELECT id, email FROM users", "WITH big AS (SELECT * FROM orders) SELECT * FROM big",
    "SELECT 1; SELECT 2", "DELETE FROM users", "DROP TABLE orders", "SELEC * FRMO users",
    "",
  ]
  for sql in samples {
    let check = @sqlcheck.check_read_only(sql)
    if check.ok {
      println("OK       [\{sql}] (\{check.statements} statement(s))")
    } else {
      println("REJECTED [\{sql}] -> \{check.reason}")
    }
  }
}
