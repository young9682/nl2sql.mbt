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
  let generate : async (String, String) -> String = (_, _) => reply
  let rejected = compare_case(
    question,
    catalog,
    input,
    Some(generate),
    structured=true,
  )
  assert_true(rejected.status == InvalidOutput)
  assert_eq(rejected.model_reply, Some(reply))
  let fixture = compare_case(question, catalog, input, None, structured=false)
  assert_true(fixture.status == CorrectRows)
  assert_eq(fixture.model_reply, None)
}
