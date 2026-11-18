///|
/// Validates references and aggregate grouping before emitting SQLite SQL.
/// The catalog is the only source of identifiers, and all literal values are bound.
pub fn compile(
  catalog : @lib.Catalog,
  plan : Plan,
) -> CompiledQuery raise PlanError {
  if plan.select.is_empty() {
    raise EmptyProjection
  }
  guard catalog.schema.find_table(plan.from_table) is Some(base) else {
    raise UnknownTable(plan.from_table)
  }
  let tables = Map([(base.name, base)])
  let joins = []
  for join in plan.joins {
    guard tables.get(join.via) is Some(via) && !tables.contains(join.table) else {
      raise InvalidJoin(join.via, join.table)
    }
    guard catalog.schema.find_table(join.table) is Some(table) else {
      raise UnknownTable(join.table)
    }
    let conditions = foreign_key_conditions(catalog.foreign_keys, via, table)
    joins.push(" JOIN " + quote_name(table.name) + " ON " + conditions)
    tables[table.name] = table
  }

  let grouped = !plan.group_by.is_empty() ||
    plan.select.any(item => !(item is Column(_)))
  let projection = plan.select.map(item => {
    match item {
      Column(column_ref) => {
        let expression = column_sql(tables, column_ref)
        if grouped && !plan.group_by.contains(column_ref) {
          raise MissingGroupBy(column_ref)
        }
        expression
      }
      CountAll => "COUNT(*)"
      Count(column_ref) => "COUNT(" + column_sql(tables, column_ref) + ")"
      Sum(column_ref) => "SUM(" + column_sql(tables, column_ref) + ")"
      Avg(column_ref) => "AVG(" + column_sql(tables, column_ref) + ")"
      Min(column_ref) => "MIN(" + column_sql(tables, column_ref) + ")"
      Max(column_ref) => "MAX(" + column_sql(tables, column_ref) + ")"
    }
  })
  let sql = StringBuilder()
  sql.write_string(
    "SELECT " + projection.join(", ") + " FROM " + quote_name(base.name),
  )
  sql.write_string(joins.join(""))
  let params = []
  if !plan.filters.is_empty() {
    let filters = plan.filters.map(filter => {
      match filter {
        Compare(column_ref, comparison, value) => {
          if value is Real(number) && !number.is_finite() {
            raise InvalidLiteral
          }
          params.push(value)
          column_sql(tables, column_ref) +
          " " +
          comparison_sql(comparison) +
          " ?"
        }
        IsNull(column_ref) => column_sql(tables, column_ref) + " IS NULL"
        IsNotNull(column_ref) => column_sql(tables, column_ref) + " IS NOT NULL"
      }
    })
    sql.write_string(" WHERE " + filters.join(" AND "))
  }
  if !plan.group_by.is_empty() {
    let keys = plan.group_by.map(column_ref => column_sql(tables, column_ref))
    sql.write_string(" GROUP BY " + keys.join(", "))
  }
  if !plan.order_by.is_empty() {
    let order = plan.order_by.map(item => {
      if item.position <= 0 || item.position > plan.select.length() {
        raise InvalidOrder(item.position)
      }
      "\{item.position}" + (if item.descending { " DESC" } else { " ASC" })
    })
    sql.write_string(" ORDER BY " + order.join(", "))
  }
  if plan.limit is Some(limit) {
    if limit <= 0 {
      raise InvalidLimit(limit)
    }
    sql.write_string(" LIMIT ?")
    params.push(Integer(limit.to_int64()))
  }
  { sql: sql.to_string(), params, }
}

///|
fn quote_name(name : String) -> String raise PlanError {
  if name.is_empty() || name.contains("\u{0}") {
    raise InvalidIdentifier(name)
  }
  "\"" + name.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn column_sql(
  tables : Map[String, @lib.Table],
  column_ref : ColumnRef,
) -> String raise PlanError {
  guard tables.get(column_ref.table) is Some(table) else {
    raise UnknownTable(column_ref.table)
  }
  if !table.columns.any(column => column.name == column_ref.column) {
    raise UnknownColumn(column_ref)
  }
  quote_name(table.name) + "." + quote_name(column_ref.column)
}

///|
fn comparison_sql(comparison : Comparison) -> String {
  match comparison {
    Equal => "="
    NotEqual => "<>"
    Less => "<"
    LessEqual => "<="
    Greater => ">"
    GreaterEqual => ">="
  }
}

///|
fn sqlite_name_key(name : String) -> String {
  let key = StringBuilder()
  for character in name {
    key.write_char(character.to_ascii_lowercase())
  }
  key.to_string()
}

///|
fn foreign_key_conditions(
  keys : Array[@lib.ForeignKey],
  via : @lib.Table,
  table : @lib.Table,
) -> String raise PlanError {
  let via_key = sqlite_name_key(via.name)
  let table_key = sqlite_name_key(table.name)
  let mut chosen = None
  for key in keys {
    let source = sqlite_name_key(key.source_table)
    let target = sqlite_name_key(key.target_table)
    let pairing = if source == via_key && target == table_key {
      Some((via, table))
    } else if source == table_key && target == via_key {
      Some((table, via))
    } else {
      None
    }
    if pairing is Some((source_table, target_table)) {
      if chosen is Some(_) {
        raise AmbiguousJoin(via.name, table.name)
      }
      chosen = Some((key, source_table, target_table))
    }
  }
  guard chosen is Some((key, source_table, target_table)) &&
    !key.source_columns.is_empty() &&
    key.source_columns.length() == key.target_columns.length() else {
    raise InvalidJoin(via.name, table.name)
  }
  let conditions = []
  for index, source_name in key.source_columns {
    guard key.target_columns[index] is Some(target_name) else {
      raise InvalidJoin(via.name, table.name)
    }
    let source_key = sqlite_name_key(source_name)
    let target_key = sqlite_name_key(target_name)
    if !source_table.columns.any(column => {
        sqlite_name_key(column.name) == source_key
      }) ||
      !target_table.columns.any(column => {
        sqlite_name_key(column.name) == target_key
      }) {
      raise InvalidJoin(via.name, table.name)
    }
    // SQLite foreign-key comparisons use the parent affinity and collation.
    // Unary plus leaves the child value intact and removes its affinity.
    conditions.push(
      quote_name(target_table.name) +
      "." +
      quote_name(target_name) +
      " = +" +
      quote_name(source_table.name) +
      "." +
      quote_name(source_name),
    )
  }
  conditions.join(" AND ")
}
