///|
#derive(Eq, Debug, FromJson)
pub(all) struct ColumnRef {
  table : String
  column : String
}

///|
#derive(Debug, FromJson)
pub(all) struct Join {
  table : String
  via : String
}

///|
#derive(Debug, FromJson(style="flat"))
pub(all) enum Projection {
  Column(ColumnRef)
  CountAll
  Count(ColumnRef)
  Sum(ColumnRef)
  Avg(ColumnRef)
  Min(ColumnRef)
  Max(ColumnRef)
}

///|
#derive(Debug, FromJson(style="flat"))
pub(all) enum Comparison {
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
}

///|
#derive(Eq, Debug, FromJson(style="flat"))
pub(all) enum Literal {
  Integer(Int64)
  Real(Double)
  Text(String)
}

///|
#derive(Debug, FromJson(style="flat"))
pub(all) enum Predicate {
  Compare(ColumnRef, Comparison, Literal)
  IsNull(ColumnRef)
  IsNotNull(ColumnRef)
}

///|
#derive(Debug, FromJson)
pub(all) struct Order {
  /// One-based index of a projected expression.
  position : Int32
  descending : Bool
}

///|
/// Inner joins use a unique declared foreign key to an already joined table.
/// Filters are combined with AND. Table and column names come from the catalog.
#derive(Debug, FromJson)
pub(all) struct Plan {
  from_table : String
  select : Array[Projection]
  joins : Array[Join]
  filters : Array[Predicate]
  group_by : Array[ColumnRef]
  order_by : Array[Order]
  limit : Int32?
}

///|
#derive(Debug)
pub(all) struct CompiledQuery {
  sql : String
  params : Array[Literal]
}

///|
#derive(Debug)
pub suberror PlanError {
  EmptyProjection
  UnknownTable(String)
  UnknownColumn(ColumnRef)
  InvalidJoin(String, String)
  AmbiguousJoin(String, String)
  MissingGroupBy(ColumnRef)
  InvalidOrder(Int32)
  InvalidLimit(Int32)
  InvalidIdentifier(String)
  InvalidLiteral
}
