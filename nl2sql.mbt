// nl2sql — natural language to SQL data Q&A engine, in MoonBit.
// M0 slice: schema model, LLM-friendly digests, DDL rendering, JSON output.

///|
/// A single column of a relational table.
pub(all) struct Column {
  name : String
  col_type : String
  nullable : Bool
  primary_key : Bool
}

///|
/// A relational table: a name and its ordered columns.
pub(all) struct Table {
  name : String
  columns : Array[Column]
}

///|
/// A database schema: an ordered list of tables.
pub(all) struct Schema {
  tables : Array[Table]
}

///|
/// Creates a column.
pub fn Column::new(
  name : String,
  col_type : String,
  nullable~ : Bool = true,
  primary_key~ : Bool = false,
) -> Column {
  { name, col_type, nullable, primary_key, }
}

///|
/// Creates a table.
pub fn Table::new(name : String, columns : Array[Column]) -> Table {
  { name, columns, }
}

///|
/// Creates a schema.
pub fn Schema::new(tables : Array[Table]) -> Schema {
  { tables, }
}

///|
/// A small e-commerce sample schema, used by tests, examples and docs.
pub fn sample_schema() -> Schema {
  Schema::new([
    Table::new("users", [
      Column::new("id", "INTEGER", nullable=false, primary_key=true),
      Column::new("email", "TEXT", nullable=false),
      Column::new("created_at", "TEXT"),
    ]),
    Table::new("orders", [
      Column::new("id", "INTEGER", nullable=false, primary_key=true),
      Column::new("user_id", "INTEGER", nullable=false),
      Column::new("amount", "REAL", nullable=false),
    ]),
  ])
}

///|
/// Finds a table by exact name; returns `None` if absent.
pub fn Schema::find_table(self : Schema, name : String) -> Table? {
  for t in self.tables {
    if t.name == name {
      return Some(t)
    }
  }
  None
}

///|
/// Renders a compact, LLM-friendly one-line-per-table description of the
/// schema. Intended to be embedded verbatim into prompts.
pub fn Schema::digest(self : Schema) -> String {
  let buf = StringBuilder()
  for t in self.tables {
    buf.write_string("table ")
    buf.write_string(t.name)
    buf.write_string("(")
    for i, c in t.columns {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(c.name)
      buf.write_string(": ")
      buf.write_string(c.col_type)
      if c.primary_key {
        buf.write_string(", pk")
      } else if !c.nullable {
        buf.write_string(", not null")
      }
    }
    buf.write_string(")\n")
  }
  buf.to_string()
}

///|
/// Renders a `CREATE TABLE` statement for this table (SQLite dialect).
pub fn Table::create_table_sql(self : Table) -> String {
  let buf = StringBuilder()
  buf.write_string("CREATE TABLE ")
  buf.write_string(self.name)
  buf.write_string(" (")
  for i, c in self.columns {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(c.name)
    buf.write_string(" ")
    buf.write_string(c.col_type)
    if c.primary_key {
      buf.write_string(" PRIMARY KEY")
    } else if !c.nullable {
      buf.write_string(" NOT NULL")
    }
  }
  buf.write_string(")")
  buf.to_string()
}

///|
/// Renders the full schema as SQLite DDL, one statement per line.
pub fn Schema::create_table_sql(self : Schema) -> String {
  let buf = StringBuilder()
  for i, t in self.tables {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(t.create_table_sql())
  }
  buf.to_string()
}

///|
/// Serializes the schema to JSON.
pub fn Schema::to_json(self : Schema) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"tables\":[")
  for i, t in self.tables {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(t.to_json_body())
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
fn Table::to_json_body(self : Table) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"name\":\"")
  buf.write_string(json_escape(self.name))
  buf.write_string("\",\"columns\":[")
  for i, c in self.columns {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(c.to_json_body())
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
fn Column::to_json_body(self : Column) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"name\":\"")
  buf.write_string(json_escape(self.name))
  buf.write_string("\",\"type\":\"")
  buf.write_string(json_escape(self.col_type))
  buf.write_string("\",\"nullable\":")
  buf.write_string(if self.nullable { "true" } else { "false" })
  buf.write_string(",\"primary_key\":")
  buf.write_string(if self.primary_key { "true" } else { "false" })
  buf.write_string("}")
  buf.to_string()
}

///|
/// Escapes a string for embedding inside a JSON string literal.
fn json_escape(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}
