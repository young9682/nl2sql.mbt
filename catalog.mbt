///|
/// A declared foreign key. Column arrays are ordered by the SQLite key sequence.
/// An unresolved target column denotes an incomplete or invalid declaration.
pub(all) struct ForeignKey {
  source_table : String
  source_columns : Array[String]
  target_table : String
  target_columns : Array[String?]
}

///|
/// A schema and its declared relationships from one database snapshot.
pub(all) struct Catalog {
  schema : Schema
  foreign_keys : Array[ForeignKey]
}
