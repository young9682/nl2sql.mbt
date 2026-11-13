///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  let schema = @lib.sample_schema()
  println(schema.digest())
  println(schema.create_table_sql())
}
