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
test "quoted finite reals and a null limit compile like canonical plan JSON" {
  let catalog = sample_catalog()
  let canonical =
    #|{"plan":{"from_table":"orders","select":["CountAll"],"joins":[],"filters":[["Compare",{"table":"orders","column":"amount"},"GreaterEqual",["Real",42.5]]],"group_by":[],"order_by":[]}}
  let compatible =
    #|{"plan":{"from_table":"orders","select":["CountAll"],"joins":[],"filters":[["Compare",{"table":"orders","column":"amount"},"GreaterEqual",["Real","4.25e1"]]],"group_by":[],"order_by":[],"limit":null}}
  guard @plan.compile_reply(catalog, canonical) is Query(expected) &&
    @plan.compile_reply(catalog, compatible) is Query(actual) else {
    fail("expected both spellings to produce a query")
  }
  assert_eq(actual.sql, expected.sql)
  assert_eq(actual.params, [Real(42.5)])
  assert_eq(actual.params, expected.params)
}

///|
test "reply normalization rejects malformed and nonfinite decimal strings" {
  let catalog = sample_catalog()
  for literal in ["42.5 extra", "1e999", "null"] {
    let reply =
      $|{"plan":{"from_table":"orders","select":["CountAll"],"joins":[],"filters":[["Compare",{"table":"orders","column":"amount"},"GreaterEqual",["Real","\{literal}"]]],"group_by":[],"order_by":[]}}
    let invalid = try {
      ignore(@plan.compile_reply(catalog, reply))
      false
    } catch {
      @plan.ReplyError::InvalidReply(_) => true
      error => raise error
    }
    assert_true(invalid)
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

///|
test "route repair requires an unambiguous declared path within two hops" {
  let tables = ["a", "b", "c", "d", "e"].map(name => {
    @lib.Table::new(name, [@lib.Column::new("id", "INTEGER")])
  })
  let schema = @lib.Schema::new(tables)
  let key = (source, target) => {
    let fk : @lib.ForeignKey = {
      source_table: source,
      source_columns: ["id"],
      target_table: target,
      target_columns: [Some("id")],
    }
    fk
  }
  let invalid =
    #|{"plan":{"from_table":"a","select":[["Column",{"table":"a","column":"id"}]],"joins":[{"table":"b","via":"missing"}],"filters":[["Compare",{"table":"d","column":"id"},"Equal",["Integer","3"]]],"group_by":[],"order_by":[]}}
  for
    keys in [
      [key("a", "d"), key("d", "a")],
      [key("a", "b"), key("b", "d"), key("a", "c"), key("c", "d")],
      [key("a", "b"), key("a", "b"), key("b", "d")],
      [key("a", "b"), key("b", "c"), key("c", "d")],
      [key("a", "b"), key("c", "d")],
    ] {
    let catalog : @lib.Catalog = { schema, foreign_keys: keys, }
    let refused = try {
      ignore(@plan.compile_reply(catalog, invalid, resolve_join_path=true))
      false
    } catch {
      @plan.PlanError::InvalidJoin(_, _) => true
      error => raise error
    }
    assert_true(refused)
  }
  let catalog : @lib.Catalog = {
    schema,
    foreign_keys: [key("A", "D"), key("a", "b"), key("b", "d")],
  }
  guard @plan.compile_reply(catalog, invalid, resolve_join_path=true)
    is Query(shortest) else {
    fail("missing direct route")
  }
  assert_false(shortest.sql.contains("JOIN \"b\""))
  assert_true(shortest.sql.contains("JOIN \"d\""))
  let valid_detour = invalid.replace_all(
    old="{\"table\":\"b\",\"via\":\"missing\"}",
    new="{\"table\":\"b\",\"via\":\"a\"},{\"table\":\"d\",\"via\":\"b\"}",
  )
  guard @plan.compile_reply(catalog, valid_detour, resolve_join_path=true)
    is Query(explicit) else {
    fail("expected explicit valid route")
  }
  assert_true(explicit.sql.contains("JOIN \"b\""))
}
