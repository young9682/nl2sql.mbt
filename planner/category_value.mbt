///|
fn can_take_es(word : StringView) -> Bool {
  ["s", "sh", "ch", "x", "z"].any(ending => word.has_suffix(ending))
}

///|
/// Keep quoted literals and exact stored categories. Try the singular only
/// when exactly one grounded candidate exists in the same column.
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
  guard category_columns.contains(field.column.to_lower()) &&
    !["\"", "'", "“", "”", "‘", "’"].any(mark => question.contains(mark)) &&
    value.iter().all(ch => ch.is_ascii_lowercase()) &&
    value.strip_suffix("s") is Some(stem) &&
    stem.length() >= 3 &&
    !["ss", "us", "is"].any(ending => value.has_suffix(ending)) else {
    return value
  }

  let alternatives = [stem.to_owned()]
  if value.strip_suffix("es") is Some(base) &&
    base.length() >= 3 &&
    can_take_es(base) {
    alternatives.push(base.to_owned())
  }
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
    [singular] => singular
    _ => value
  }
}
