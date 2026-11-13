// Blackbox tests for the public API of `young9682/nl2sql`.

///|
test "digest renders one compact line per table" {
  inspect(
    @nl2sql.sample_schema().digest(),
    content=(
      #|table users(id: INTEGER, pk, email: TEXT, not null, created_at: TEXT)
      #|table orders(id: INTEGER, pk, user_id: INTEGER, not null, amount: REAL, not null)
      #|
    ),
  )
}

///|
test "create_table_sql renders SQLite DDL" {
  inspect(
    @nl2sql.sample_schema().create_table_sql(),
    content=(
      #|CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, created_at TEXT)
      #|CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, amount REAL NOT NULL)
    ),
  )
}

///|
test "to_json serializes the full schema" {
  inspect(
    @nl2sql.sample_schema().to_json(),
    content=(
      #|{"tables":[{"name":"users","columns":[{"name":"id","type":"INTEGER","nullable":false,"primary_key":true},{"name":"email","type":"TEXT","nullable":false,"primary_key":false},{"name":"created_at","type":"TEXT","nullable":true,"primary_key":false}]},{"name":"orders","columns":[{"name":"id","type":"INTEGER","nullable":false,"primary_key":true},{"name":"user_id","type":"INTEGER","nullable":false,"primary_key":false},{"name":"amount","type":"REAL","nullable":false,"primary_key":false}]}]}
    ),
  )
}

///|
test "find_table matches exact names and misses unknown ones" {
  let schema = @nl2sql.sample_schema()
  assert_true(schema.find_table("orders") is Some(_))
  assert_true(schema.find_table("orderz") is None)
}

///|
test "json output escapes special characters" {
  let schema = @nl2sql.Schema::{
    tables: [
      @nl2sql.Table::{
        name: "we\"ird\nname",
        columns: [
          @nl2sql.Column::{
            name: "a\\b",
            col_type: "TEXT",
            nullable: true,
            primary_key: false,
          },
        ],
      },
    ],
  }
  inspect(
    schema.to_json(),
    content=(
      #|{"tables":[{"name":"we\"ird\nname","columns":[{"name":"a\\b","type":"TEXT","nullable":true,"primary_key":false}]}]}
    ),
  )
}
