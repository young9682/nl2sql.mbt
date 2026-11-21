///|
/// Only repair projections with two explicit endpoint tables. An unreferenced
/// join in a count or grouped query can determine the rows being aggregated.
fn replacement_path(catalog : @lib.Catalog, plan : Plan) -> Array[Join]? {
  guard plan.group_by.is_empty() else { return None }
  let endpoints : Set[String] = Set([])
  for item in plan.select {
    guard item is Column(column) else { return None }
    endpoints.add(column.table)
  }
  for predicate in plan.filters {
    match predicate {
      Compare(column, _, _) | IsNull(column) | IsNotNull(column) =>
        endpoints.add(column.table)
    }
  }
  let base = plan.from_table
  guard endpoints.length() == 2 && endpoints.contains(base) else { return None }
  endpoints.remove(base)
  let target = endpoints.to_array()[0]
  guard catalog.schema.find_table(base) is Some(_) &&
    catalog.schema.find_table(target) is Some(_) else {
    return None
  }
  let from_base = neighbor_counts(catalog.foreign_keys, base)
  let target_key = sqlite_name_key(target)
  if from_base.get(target_key) is Some(n) {
    return if n == 1 { Some([{ via: base, table: target, }]) } else { None }
  }
  let from_target = neighbor_counts(catalog.foreign_keys, target)
  let mut bridge = None
  for table in catalog.schema.tables {
    let key = sqlite_name_key(table.name)
    if from_base.get(key) is Some(left) && from_target.get(key) is Some(right) {
      if bridge is Some(_) || left != 1 || right != 1 {
        return None
      }
      bridge = Some(table.name)
    }
  }
  guard bridge is Some(via) else { return None }
  Some([{ via: base, table: via, }, { via, table: target, }])
}

///|
fn neighbor_counts(
  keys : Array[@lib.ForeignKey],
  table : String,
) -> Map[String, Int32] {
  let name = sqlite_name_key(table)
  let counts = Map([])
  for fk in keys {
    let source = sqlite_name_key(fk.source_table)
    let target = sqlite_name_key(fk.target_table)
    let neighbor = if source == name && target != name {
      target
    } else if target == name && source != name {
      source
    } else {
      continue
    }
    counts[neighbor] = counts.get(neighbor).unwrap_or(0) + 1
  }
  counts
}
