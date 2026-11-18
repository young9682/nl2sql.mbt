///|
/// Reads regular tables, visible columns, and declared foreign keys from `main`.
/// Views and virtual tables are outside the catalog exposed to the planner.
pub fn read_catalog(
  path : String,
  timeout_ms~ : Int32 = 5000,
) -> @lib.Catalog raise QueryError {
  let metadata = execute(path, None, [], 16384, timeout_ms)
  if metadata.truncated {
    raise InvalidSchema("database schema exceeds the metadata row limit")
  }
  let tables = []
  let by_name : Map[String, @lib.Table] = Map([])
  let foreign_keys : Array[@lib.ForeignKey] = []
  let mut last_key = None
  for row in metadata.rows {
    match row {
      [
        Integer(0L),
        Text(table_name),
        Text(name),
        Text(col_type),
        Integer(pk),
        Integer(not_null),
        ..,
      ] => {
        let table = match by_name.get(table_name) {
          Some(table) => table
          None => {
            let table = @lib.Table::new(table_name, [])
            by_name[table_name] = table
            tables.push(table)
            table
          }
        }
        table.columns.push(
          @lib.Column::new(
            name,
            col_type,
            nullable=not_null == 0L,
            primary_key=pk > 0L,
          ),
        )
      }
      [
        Integer(1L),
        Text(source_table),
        Text(source_column),
        Text(target_table),
        _,
        _,
        Integer(key_id),
        _,
        target,
      ] => {
        let key = (source_table, key_id)
        if last_key != Some(key) {
          foreign_keys.push({
            source_table,
            target_table,
            source_columns: [],
            target_columns: [],
          })
          last_key = Some(key)
        }
        let relation = foreign_keys[foreign_keys.length() - 1]
        relation.source_columns.push(source_column)
        relation.target_columns.push(
          match target {
            Text(column) => Some(column)
            Null => None
            _ => raise InvalidSchema("invalid foreign key column")
          },
        )
      }
      _ => raise InvalidSchema("unexpected SQLite metadata")
    }
  }
  { schema: @lib.Schema::new(tables), foreign_keys, }
}
