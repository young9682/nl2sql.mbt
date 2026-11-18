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
