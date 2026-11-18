///|
/// A value with its SQLite storage class preserved.
#derive(Eq, Debug)
pub(all) enum Value {
  Null
  Integer(Int64)
  Real(Double)
  Text(String)
  Blob(Bytes)
}

///|
/// Columns and cells are in SQLite result order. Column names may repeat.
#derive(Debug, ToJson)
pub(all) struct QueryResult {
  columns : Array[String]
  rows : Array[Array[Value]]
  truncated : Bool
}

///|
#derive(Debug)
pub suberror QueryError {
  InvalidInput(String)
  OpenFailed(Int32, String)
  EmptyStatement
  MultipleStatements
  Rejected(String)
  ParameterCount(Int32, Int32)
  InvalidText
  InvalidSchema(String)
  TimedOut
  SqliteError(Int32, String)
}

///|
/// Executes one query on an existing local SQLite file. Each call has its own
/// read-only connection and binds positional parameters in SQLite index order.
pub fn query(
  path : String,
  sql : String,
  params~ : Array[Value] = [],
  max_rows~ : Int32 = 100,
  timeout_ms~ : Int32 = 5000,
) -> QueryResult raise QueryError {
  execute(path, Some(sql), params, max_rows, timeout_ms)
}

///|
fn execute(
  path : String,
  sql : String?,
  params : Array[Value],
  max_rows : Int32,
  timeout_ms : Int32,
) -> QueryResult raise QueryError {
  if path.is_empty() ||
    path == ":memory:" ||
    path.has_prefix("file:") ||
    path.contains("\u{0}") {
    raise InvalidInput("expected a local database file path")
  }
  if max_rows <= 0 || timeout_ms <= 0 {
    raise InvalidInput("max_rows and timeout_ms must be positive")
  }
  let sql_bytes = match sql {
    Some(sql) => {
      if sql.contains("\u{0}") {
        raise InvalidInput("SQL contains a NUL character")
      }
      let bytes = @utf8.encode(sql + "\u{0}")
      if bytes.length() > 64 * 1024 + 1 {
        raise InvalidInput("SQL text is longer than 64 KiB")
      }
      Some(bytes)
    }
    None => None
  }
  let handle = open_read_only(@utf8.encode(path + "\u{0}"), timeout_ms)
  if handle == 0L {
    raise OpenFailed(7, "could not allocate the SQLite connection")
  }
  defer close(handle)
  let status = open_status(handle)
  if status != 0 {
    raise OpenFailed(status, sqlite_message(handle, status))
  }
  let status = match sql_bytes {
    Some(bytes) => prepare(handle, bytes)
    None => prepare_catalog(handle)
  }
  match status {
    0 => ()
    -1 => raise EmptyStatement
    -2 => raise MultipleStatements
    -3 => raise Rejected("expected a read-only query returning rows")
    _ => raise execution_error(handle, status)
  }
  let expected = parameter_count(handle)
  if params.length() != expected {
    raise ParameterCount(expected, params.length())
  }
  for offset, param in params {
    let index = offset + 1
    let status = match param {
      Null => bind_null(handle, index)
      Integer(value) => bind_integer(handle, index, value)
      Real(value) => bind_real(handle, index, value)
      Text(value) => {
        let bytes = @utf8.encode(value)
        bind_text(handle, index, bytes, bytes.length())
      }
      Blob(value) => bind_blob(handle, index, value, value.length())
    }
    if status != 0 {
      raise execution_error(handle, status)
    }
  }
  let count = column_count(handle)
  let columns = []
  for index in 0..<count {
    columns.push(decode_text(column_name(handle, index)))
  }
  let rows = []
  for ;; {
    let status = step(handle)
    match status {
      100 => {
        if rows.length() == max_rows {
          return { columns, rows, truncated: true, }
        }
        let row = []
        for index in 0..<count {
          row.push(read_cell(handle, index))
        }
        rows.push(row)
      }
      101 => return { columns, rows, truncated: false, }
      _ => raise execution_error(handle, status)
    }
  }
}

///|
fn decode_text(bytes : Bytes) -> String raise QueryError {
  @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise InvalidText
  }
}

///|
fn sqlite_message(handle : Int64, status : Int32) -> String {
  @utf8.decode_lossy(error_message(handle, status)[:])
}

///|
fn execution_error(handle : Int64, status : Int32) -> QueryError {
  match status {
    9 => TimedOut
    23 => Rejected(sqlite_message(handle, status))
    _ => SqliteError(status, sqlite_message(handle, status))
  }
}

///|
fn read_cell(handle : Int64, index : Int32) -> Value raise QueryError {
  match column_type(handle, index) {
    1 => Integer(column_integer(handle, index))
    2 => Real(column_real(handle, index))
    3 => Text(decode_text(column_text(handle, index)))
    4 => Blob(column_blob(handle, index))
    _ => Null
  }
}
