///|
fn can_take_es(word : StringView) -> Bool {
  ["s", "sh", "ch", "x", "z"].any(ending => word.has_suffix(ending))
}

///|
/// Keep quoted literals and exact stored categories. Use a grounded alternative
/// only when exactly one candidate exists in the same column.
fn stored_category_value(
  path : String,
  catalog : @lib.Catalog,
  field : @plan.ColumnRef,
  question : String,
  value : String,
  timeout_ms : Int32,
) -> String {
  let category_columns = [
    "category", "kind", "item", "type", "format", "shape", "species", "medium",
  ]
  let column = field.column.to_lower()
  guard category_columns.contains(column) &&
    !["\"", "'", "“", "”", "‘", "’"].any(mark => question.contains(mark)) else {
    return value
  }
  let alternatives = category_alternatives(value, column)
  guard !alternatives.is_empty() else { return value }
  let lookup : @plan.Plan = {
    from_table: field.table,
    select: [Column(field)],
    joins: [],
    filters: [Compare(field, Equal, Text(value))],
    group_by: [],
    order_by: [],
    limit: None,
  }
  let query = @plan.compile(catalog, lookup) catch { _ => return value }
  let candidates = [value] + alternatives
  let expressions = candidates.map(_ => "EXISTS(" + query.sql + ")")
  let result = @sqlite.query(
    path,
    "SELECT " + expressions.join(", "),
    params=candidates.map(literal => @sqlite.Value::Text(literal)),
    max_rows=1,
    timeout_ms~,
  ) catch {
    _ => return value
  }
  guard result.rows is [[Integer(0L), .. matches]] else { return value }
  let present = []
  for index, match_found in matches {
    if match_found is Integer(1L) {
      present.push(alternatives[index])
    }
  }
  match present {
    [stored] => stored
    _ => value
  }
}

///|
fn category_alternatives(value : String, column : String) -> Array[String] {
  // A model can include the column name when it copies an unquoted category.
  // Look up the remaining phrase exactly.
  if value.split_once(" ") is Some((prefix, suffix)) &&
    prefix.to_owned().to_lower() == column &&
    !suffix.is_empty() &&
    suffix.trim() == suffix {
    return [suffix.to_owned()]
  }
  guard value.iter().all(ch => ch.is_ascii_lowercase()) &&
    value.strip_suffix("s") is Some(stem) &&
    stem.length() >= 3 &&
    !["ss", "us", "is"].any(ending => value.has_suffix(ending)) else {
    return []
  }
  let alternatives = [stem.to_owned()]
  if value.strip_suffix("es") is Some(base) &&
    base.length() >= 3 &&
    can_take_es(base) {
    alternatives.push(base.to_owned())
  }
  alternatives
}
