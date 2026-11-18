///|
fn low_stock(
  path : String,
  reorder_at : Int64,
  max_rows~ : Int32 = 100,
) -> @sqlite.QueryResult raise @sqlite.QueryError {
  @sqlite.query(
    path,
    "SELECT s.region, p.title, s.available FROM stock AS s JOIN products AS p ON p.region = s.region AND p.sku = s.sku WHERE s.available <= ? ORDER BY s.available, s.region, s.sku",
    params=[Integer(reorder_at)],
    max_rows~,
  )
}

///|
fn report_json(result : @sqlite.QueryResult) -> Json {
  let status = if result.truncated { "partial" } else { "complete" }
  { "status": Json::string(status), "inventory": @json.to_json(result) }
}

///|
fn main {
  guard @env.args() is [_, path, reorder_at, max_rows] else {
    println("Usage: inventory-report DATABASE REORDER_AT MAX_ROWS")
    @env.exit(2)
  }
  let threshold = @string.parse_int64(reorder_at) catch {
    _ => {
      println("REORDER_AT must be an integer.")
      @env.exit(2)
    }
  }
  let limit = @string.parse_int(max_rows) catch {
    _ => {
      println("MAX_ROWS must be a positive integer.")
      @env.exit(2)
    }
  }
  if threshold < 0L || limit <= 0 {
    println("REORDER_AT must be nonnegative and MAX_ROWS must be positive.")
    @env.exit(2)
  }
  let result = low_stock(path, threshold, max_rows=limit) catch {
    error => {
      println(@debug.to_string(error))
      @env.exit(1)
    }
  }
  println(report_json(result).stringify(indent=2))
}
