///|
test "row comparison preserves multiplicity and respects requested ordering" {
  let first : Json = [["Integer", "1"]]
  let second : Json = [["Integer", "2"]]
  assert_true(rows_match([first, second], [second, first], ordered=false))
  assert_false(rows_match([first, second], [second, first], ordered=true))
  assert_false(rows_match([first, first], [first], ordered=false))
}

///|
test "report metrics keep errors and false abstentions in the denominators" {
  let summary = summarize(
    [
      CorrectRows,
      FalseAbstention,
      InvalidOutput,
      CorrectAbstention,
      ProviderFailure,
    ],
    3,
    2,
  )
  assert_true(
    summary
    is {
      "result_accuracy": { "count": 1, "total": 3, .. },
      "invalid_output_rate": { "count": 1, "total": 5, .. },
      "correct_abstention_rate": { "count": 1, "total": 2, .. },
      "false_abstention_rate": { "count": 1, "total": 3, .. },
      "provider_failures": 1,
      ..
    },
  )
}

///|
async test "evaluation keeps the raw live reply when it rejects model output" {
  let catalog = @sqlite.read_catalog(database)
  let question : Case = {
    id: "malformed-reply",
    question: "How many users are there?",
    ordered: false,
    expected_rows: Some([[["Integer", "2"]]]),
    fixture_plan: Json::null(),
    fixture_sql: { "sql": "SELECT COUNT(*) FROM users" },
  }
  let input = @planner.model_input(catalog, question.question)
  let reply = "This is not a JSON object."
  let support =
    #|{"supported":true}
  let live : LiveModel = {
    assess: (_, _) => support,
    generate: (_, _) => reply,
  }
  let rejected = compare_case(
    database,
    question,
    catalog,
    input,
    Some(live),
    structured=true,
  )
  assert_true(rejected.status == InvalidOutput)
  assert_eq(rejected.answerability_reply, Some(support))
  assert_eq(rejected.model_reply, Some(reply))
  assert_eq(rejected.rejected_plan_reply, Some(reply))
  let fixture = compare_case(
    database,
    question,
    catalog,
    input,
    None,
    structured=false,
  )
  assert_true(fixture.status == CorrectRows)
  assert_eq(fixture.model_reply, None)
  assert_eq(fixture.rejected_plan_reply, None)
}

///|
async test "both live paths keep the assessment and skip generation on a refusal" {
  let catalog = @sqlite.read_catalog(database)
  let question : Case = {
    id: "missing-data",
    question: "When did each user first log in?",
    ordered: false,
    expected_rows: None,
    fixture_plan: Json::null(),
    fixture_sql: Json::null(),
  }
  let input = @planner.model_input(catalog, question.question)
  let assessment : Json = {
    "schema_review": "{\"missing_column\":[\"users\",\"first_login_at\"]}",
  }
  let refusal = assessment.stringify()
  for structured in [true, false] {
    let result = compare_case(
      database,
      question,
      catalog,
      input,
      Some({
        assess: (_, _) => refusal,
        generate: (_, _) => fail("unexpected generation after refusal"),
      }),
      structured~,
    )
    assert_true(result.status == CorrectAbstention)
    assert_eq(result.answerability_reply, Some(refusal))
    assert_eq(result.model_reply, None)
    assert_eq(result.sql, None)
  }
}

///|
async test "repair direct and two-hop route failures against the radio row oracles" {
  let path = "eval/route-dev/radio.db"
  let catalog = @sqlite.read_catalog(path)
  let questions : Array[Case] = @json.from_json(
    @json.parse(@fs.read_file("eval/route-dev/questions.json").text()),
  )
  for question in questions {
    let fixture = question.fixture_plan
    let canonical = @planner.execute_reply(path, catalog, fixture.stringify())
    guard canonical is Queried(expected) else { fail(question.id) }
    guard fixture is { "plan": Object(fields), .. } else { fail(question.id) }
    guard fields.get("joins") is Some(Array(steps)) else { fail(question.id) }
    guard steps[0] is { "via": String(base), .. } &&
      steps[steps.length() - 1] is { "table": String(target), .. } else {
      fail(question.id)
    }
    // For a two-hop case omit the bridge. For a direct case detour through
    // another known table that cannot connect these endpoints.
    fields["joins"] = if steps.length() == 2 {
      [{ "via": Json::string(base), "table": Json::string(target) }]
    } else {
      let detour = if base == "shows" && target == "studios" {
        "episodes"
      } else {
        "bookings"
      }
      [
        { "via": Json::string(base), "table": Json::string(detour) },
        { "via": Json::string(detour), "table": Json::string(target) },
      ]
    }
    let invalid = fixture.stringify()
    let rejected = try {
      ignore(@planner.execute_reply(path, catalog, invalid))
      false
    } catch {
      @plan.PlanError::InvalidJoin(_, _) => true
      error => raise error
    }
    assert_true(rejected)
    let fixed = @planner.execute_reply(
      path,
      catalog,
      invalid,
      resolve_join_path=true,
    )
    guard fixed is Queried(actual) else { fail(question.id) }
    assert_eq(actual.sql, expected.sql)
    assert_eq(actual.params, expected.params)
    assert_true(
      grade_rows(question, actual.sql, actual.params, actual.result).status ==
      CorrectRows,
    )
  }
}
