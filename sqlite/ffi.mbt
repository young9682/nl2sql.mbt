///|
#borrow(path)
extern "C" fn open_read_only(path : Bytes, timeout_ms : Int32) -> Int64 = "nl2sql_sqlite_open"

///|
extern "C" fn close(handle : Int64) = "nl2sql_sqlite_close"

///|
extern "C" fn open_status(handle : Int64) -> Int32 = "nl2sql_sqlite_open_status"

///|
extern "C" fn error_message(handle : Int64, status : Int32) -> Bytes = "nl2sql_sqlite_error_message"

///|
#borrow(sql)
extern "C" fn prepare(handle : Int64, sql : Bytes) -> Int32 = "nl2sql_sqlite_prepare"

///|
extern "C" fn prepare_catalog(handle : Int64) -> Int32 = "nl2sql_sqlite_prepare_catalog"

///|
extern "C" fn parameter_count(handle : Int64) -> Int32 = "nl2sql_sqlite_parameter_count"

///|
extern "C" fn bind_null(handle : Int64, index : Int32) -> Int32 = "nl2sql_sqlite_bind_null"

///|
extern "C" fn bind_integer(
  handle : Int64,
  index : Int32,
  value : Int64,
) -> Int32 = "nl2sql_sqlite_bind_integer"

///|
extern "C" fn bind_real(handle : Int64, index : Int32, value : Double) -> Int32 = "nl2sql_sqlite_bind_real"

///|
#borrow(value)
extern "C" fn bind_text(
  handle : Int64,
  index : Int32,
  value : Bytes,
  length : Int32,
) -> Int32 = "nl2sql_sqlite_bind_text"

///|
#borrow(value)
extern "C" fn bind_blob(
  handle : Int64,
  index : Int32,
  value : Bytes,
  length : Int32,
) -> Int32 = "nl2sql_sqlite_bind_blob"

///|
extern "C" fn step(handle : Int64) -> Int32 = "nl2sql_sqlite_step"

///|
extern "C" fn column_count(handle : Int64) -> Int32 = "nl2sql_sqlite_column_count"

///|
extern "C" fn column_name(handle : Int64, index : Int32) -> Bytes = "nl2sql_sqlite_column_name"

///|
extern "C" fn column_type(handle : Int64, index : Int32) -> Int32 = "nl2sql_sqlite_column_type"

///|
extern "C" fn column_integer(handle : Int64, index : Int32) -> Int64 = "nl2sql_sqlite_column_integer"

///|
extern "C" fn column_real(handle : Int64, index : Int32) -> Double = "nl2sql_sqlite_column_real"

///|
extern "C" fn column_text(handle : Int64, index : Int32) -> Bytes = "nl2sql_sqlite_column_text"

///|
extern "C" fn column_blob(handle : Int64, index : Int32) -> Bytes = "nl2sql_sqlite_column_blob"
