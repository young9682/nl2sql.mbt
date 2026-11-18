///|
fn sample_catalog() -> @lib.Catalog {
  {
    schema: @lib.sample_schema(),
    foreign_keys: [
      {
        source_table: "orders",
        source_columns: ["user_id"],
        target_table: "USERS",
        target_columns: [Some("ID")],
      },
    ],
  }
}

///|
fn aggregate_plan() -> @plan.Plan {
  let email : @plan.ColumnRef = { table: "users", column: "email", }
  {
    from_table: "users",
    select: [Column(email), Sum({ table: "orders", column: "amount", })],
    joins: [{ table: "orders", via: "users", }],
    filters: [Compare(email, Equal, Text("ann's@example.com"))],
    group_by: [email],
    order_by: [{ position: 2, descending: true, }],
    limit: Some(2),
  }
}

///|
test "compile a grouped join deterministically and bind filter and limit values" {
  let catalog = sample_catalog()
  let plan = aggregate_plan()
  let first = @plan.compile(catalog, plan)
  let second = @plan.compile(catalog, plan)
  assert_eq(first.sql, second.sql)
  assert_eq(first.params, second.params)
  assert_eq(first.params, [Text("ann's@example.com"), Integer(2L)])
  let expected =
    #|SELECT "users"."email", SUM("orders"."amount") FROM "users" JOIN "orders" ON "users"."ID" = +"orders"."user_id" WHERE "users"."email" = ? GROUP BY "users"."email" ORDER BY 2 DESC LIMIT ?
  assert_eq(first.sql, expected)
}

///|
test "resolve each column of a composite key in declared order" {
  let catalog : @lib.Catalog = {
    schema: @lib.Schema::new([
      @lib.Table::new("line item", [
        @lib.Column::new("part", "TEXT"),
        @lib.Column::new("region", "TEXT"),
      ]),
      @lib.Table::new("inventory", [
        @lib.Column::new("part", "TEXT"),
        @lib.Column::new("region", "TEXT"),
      ]),
    ]),
    foreign_keys: [
      {
        source_table: "line item",
        source_columns: ["part", "region"],
        target_table: "inventory",
        target_columns: [Some("part"), Some("region")],
      },
    ],
  }
  let query = @plan.compile(catalog, {
    from_table: "line item",
    select: [CountAll],
    joins: [{ table: "inventory", via: "line item", }],
    filters: [],
    group_by: [],
    order_by: [],
    limit: None,
  })
  let expected =
    #|SELECT COUNT(*) FROM "line item" JOIN "inventory" ON "inventory"."part" = +"line item"."part" AND "inventory"."region" = +"line item"."region"
  assert_eq(query.sql, expected)
}

///|
fn compile_error(catalog : @lib.Catalog, plan : @plan.Plan) -> @plan.PlanError? {
  ignore(@plan.compile(catalog, plan)) catch {
    error => return Some(error)
  }
  None
}

///|
test "reject unknown columns, out-of-scope tables, and ambiguous joins" {
  let catalog = sample_catalog()
  let plan = aggregate_plan()
  let unknown = compile_error(catalog, {
    ..plan,
    select: [Sum({ table: "orders", column: "missing", })],
  })
  assert_true(unknown is Some(@plan.PlanError::UnknownColumn(_)))
  let out_of_scope = compile_error(catalog, { ..plan, joins: [], })
  assert_true(out_of_scope is Some(@plan.PlanError::UnknownTable("orders")))
  let unrelated = compile_error({ ..catalog, foreign_keys: [], }, plan)
  assert_true(
    unrelated is Some(@plan.PlanError::InvalidJoin("users", "orders")),
  )
  let key = catalog.foreign_keys[0]
  let ambiguous = compile_error({ ..catalog, foreign_keys: [key, key], }, plan)
  assert_true(
    ambiguous is Some(@plan.PlanError::AmbiguousJoin("users", "orders")),
  )
}

///|
test "require valid grouping, projected order positions, and a positive limit" {
  let catalog = sample_catalog()
  let plan = aggregate_plan()
  let ungrouped = compile_error(catalog, { ..plan, group_by: [], })
  assert_true(ungrouped is Some(@plan.PlanError::MissingGroupBy(_)))
  let order = compile_error(catalog, {
    ..plan,
    order_by: [{ position: 3, descending: true, }],
  })
  assert_true(order is Some(@plan.PlanError::InvalidOrder(3)))
  let limit = compile_error(catalog, { ..plan, limit: Some(-1), })
  assert_true(limit is Some(@plan.PlanError::InvalidLimit(-1)))
}
