///|
let fixture = "sqlite/fixtures/orders.db"

///|
fn schema_review_reply(reply : String) -> String {
  let assessment : Json = { "schema_review": Json::string(reply) }
  assessment.stringify()
}

///|
async test "an optional assessment can decline without asking for a plan" {
  let result = @planner.ask(
    fixture,
    "When did each user first log in?",
    (_, _) => fail("unexpected plan request"),
    assess=Some((catalog, _) => {
      assert_true(catalog.schema.find_table("users") is Some(_))
      "{\"no_answer\":\"The database does not record logins.\"}"
    }),
  )
  assert_true(result is NoAnswer("The database does not record logins."))
}

///|
test "an assessment must make one unambiguous decision" {
  assert_eq(@planner.parse_answerability("{\"supported\":true}"), None)
  assert_eq(@planner.parse_answerability("{\"missing_fact\":null}"), None)
  assert_eq(
    @planner.parse_answerability(
      "{\"missing_fact\":\"Warning levels are absent.\"}",
    ),
    Some("Warning levels are absent."),
  )
  let malformed = [
    "{}",
    "{\"supported\":false}",
    "{\"no_answer\":\" \"}",
    "{\"supported\":true,\"no_answer\":\"missing data\"}",
    "{\"supported\":true,\"supported\":false}",
    "{\"missing_fact\":42}",
    "{\"missing_fact\":\" \"}",
    "{\"supported\":true,\"missing_fact\":\"missing data\"}",
    schema_review_reply("{\"no_answer\":\"A row value is missing.\"}"),
    schema_review_reply("{\"missing_column\":[\"orders\"]}"),
  ]
  for reply in malformed {
    let rejected = try {
      ignore(@planner.parse_answerability(reply))
      false
    } catch {
      @planner.PlannerError::InvalidReply(_) => true
      error => raise error
    }
    assert_true(rejected)
  }
}

///|
test "schema review verifies the table and column against the full catalog" {
  let catalog = @sqlite.read_catalog(fixture)
  let absent = schema_review_reply(
    "{\"missing_column\":[\"ORDERS\",\"dispatch_date\"]}",
  )
  assert_eq(
    @planner.parse_answerability(absent, catalog=Some(catalog)),
    Some("The schema has no column for ORDERS.dispatch_date."),
  )
  assert_eq(@planner.parse_answerability(absent), None)
  for
    raw in [
      "{\"missing_column\":null}", "{\"missing_column\":[\"orders\",\"AMOUNT\"]}",
      "{\"missing_column\":[\"orders\",\"name\"]}", "{\"missing_column\":[\"unlisted_table\",\"dispatch_date\"]}",
      "{\"missing_column\":[\"orders\",\"8102\"]}",
    ] {
    assert_eq(
      @planner.parse_answerability(
        schema_review_reply(raw),
        catalog=Some(catalog),
      ),
      None,
    )
  }
}

///|
async test "schema review preserves an initial refusal and lets an empty query run" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group() <| group => {
    let initial_refusal = "{\"no_answer\":\"The schema has no logins.\"}"
    let review_refusal = "{\"missing_column\":[\"orders\",\"contract_rate\"]}"
    group.spawn_bg(() => {
      for
        (review, reply) in [
          (false, initial_refusal),
          (false, "{\"supported\":true}"),
          (true, review_refusal),
          (false, "{\"supported\":true}"),
          (true, "{\"missing_column\":[\"orders\",\"amount\"]}"),
        ] {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        let request = @json.parse(connection.read_all().text())
        guard request
          is { "messages": [{ "content": String(prompt), .. }, ..], .. } else {
          fail("expected a system prompt")
        }
        assert_eq(prompt.contains("exactly one key missing_column"), review)
        let response : Json = {
          "choices": [{ "message": { "content": Json::string(reply) } }],
        }
        connection.send_response(200, "OK")
        connection.write(response.stringify())
        connection.end_response()
      }
    })
    let assess = @planner.openai_answerability_model(
      "http://\{server.addr}/v1/chat/completions",
      "test-model",
      request_timeout_ms=2000,
    )
    let catalog = @sqlite.read_catalog(fixture)
    assert_eq(
      assess(catalog, "When did each user first log in?"),
      initial_refusal,
    )
    assert_eq(
      assess(catalog, "What were the contract rates?"),
      schema_review_reply(review_refusal),
    )
    let empty_plan =
      #|{"plan":{"from_table":"orders","select":[["Column",{"table":"orders","column":"id"}]],"joins":[],"filters":[["Compare",{"table":"orders","column":"amount"},"Greater",["Real",1000]]],"group_by":[],"order_by":[]}}
    let empty = @planner.ask(
      fixture,
      "List order IDs for amounts over 1000.",
      (_, _) => empty_plan,
      assess=Some(assess),
    )
    guard empty is Queried(evidence) else { fail("expected an executed query") }
    assert_true(evidence.result.rows.is_empty())
  }
}

///|
async test "ask turns a structured model reply into an executed join and evidence" {
  let result = @planner.ask(fixture, "What did each user spend?", (
    instructions,
    input,
  ) => {
    assert_true(instructions.contains("foreign key"))
    assert_true(input.contains("What did each user spend?"))
    assert_true(input.contains("user_id"))
    let reply =
      #|{"plan":{"from_table":"users","select":[["Column",{"table":"users","column":"name"}],["Sum",{"table":"orders","column":"amount"}]],"joins":[{"table":"orders","via":"users"}],"filters":[],"group_by":[{"table":"users","column":"name"}],"order_by":[{"position":2,"descending":true}],"limit":2}}
    reply
  })
  guard result is Queried(evidence) else { fail("expected query evidence") }
  assert_eq(evidence.result.rows, [
    [Text("林"), Real(50.0)],
    [Text("Sam"), Real(20.0)],
  ])
  assert_eq(evidence.params, [Integer(2L)])
  assert_true(evidence.sql.contains("LIMIT ?"))
  assert_eq(evidence.catalog.foreign_keys.length(), 2)
}

///|
test "an integer filter preserves 64-bit values through JSON and binding" {
  let catalog = @sqlite.read_catalog(fixture)
  let payload =
    #|{"plan":{"from_table":"orders","select":[["Column",{"table":"orders","column":"id"}]],"joins":[],"filters":[["Compare",{"table":"orders","column":"id"},"Equal",["Integer","9007199254740993"]]],"group_by":[],"order_by":[]}}
  let result = @planner.execute_reply(fixture, catalog, payload)
  guard result is Queried(evidence) else { fail("expected query evidence") }
  assert_eq(evidence.params, [Integer(9007199254740993L)])
  assert_eq(evidence.result.rows, [[Integer(9007199254740993L)]])
}

///|
test "refusal and invalid plans do not open data queries" {
  let catalog = @sqlite.read_catalog(fixture)
  let missing_db = "sqlite/fixtures/missing.db"
  let refusal = @planner.execute_reply(
    missing_db, catalog, "{\"no_answer\":\"no costs are recorded\"}",
  )
  assert_true(refusal is NoAnswer("no costs are recorded"))
  let malformed = @planner.execute_reply(
    missing_db, catalog, "{\"plan\":{},\"plan\":{}}",
  ) catch {
    @planner.PlannerError::InvalidReply(_) => NoAnswer("invalid")
    error => raise error
  }
  assert_true(malformed is NoAnswer("invalid"))
  let unknown_column =
    #|{"plan":{"from_table":"orders","select":[["Column",{"table":"orders","column":"profit"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}
  let rejected = @planner.execute_reply(missing_db, catalog, unknown_column) catch {
    @plan.PlanError::UnknownColumn(_) => NoAnswer("invalid column")
    error => raise error
  }
  assert_true(rejected is NoAnswer("invalid column"))
}

///|
async test "OpenAI-compatible adapter sends JSON and reads a text choice" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group() <| group => {
    group.spawn_bg(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_eq(request.path, "/v1/chat/completions")
      assert_eq(
        request.headers.get(@http.CaseInsensitiveString("authorization")),
        Some("Bearer test-token"),
      )
      let payload = @json.parse(connection.read_all().text())
      assert_true(
        payload
        is {
          "model": "test-model",
          "messages": [
            { "role": "system", "content": "instructions", .. },
            { "role": "user", "content": "input", .. },
          ],
          ..
        },
      )
      let response =
        #|{"choices":[{"message":{"content":"reply"}}]}
      connection.send_response(200, "OK")
      connection.write(response)
      connection.end_response()
    })
    let callback = @planner.openai_model(
      "http://\{server.addr}/v1/chat/completions",
      "test-model",
      api_key="test-token",
    )
    assert_eq(callback("instructions", "input"), "reply")
  }
}

///|
async test "an opted-in retry uses declared edges and revalidates the replacement" {
  let path = "eval/join-dev/depot.db"
  let question = "Which bay codes occur in reader R7 scans?"
  let invalid =
    #|{"plan":{"from_table":"scans","select":[["Column",{"table":"bays","column":"code"}]],"joins":[{"table":"bays","via":"scans"}],"filters":[],"group_by":[],"order_by":[]}}
  let valid =
    #|{"plan":{"from_table":"scans","select":[["Column",{"table":"bays","column":"code"}]],"joins":[{"table":"crates","via":"scans"},{"table":"bays","via":"crates"}],"filters":[["Compare",{"table":"scans","column":"reader"},"Equal",["Text","R7"]]],"group_by":[],"order_by":[{"position":1,"descending":false}]}}
  let catalog = @sqlite.read_catalog(path)
  assert_true(@planner.plan_retry_request(catalog, question, valid) is None)
  assert_true(
    @planner.plan_retry_request(
      catalog, question, "{\"no_answer\":\"missing\"}",
    )
    is None,
  )
  for (accepted, replacement) in [(true, valid), (false, invalid)] {
    let mut calls = 0
    let result = Some(
      @planner.ask(
        path,
        question,
        (_, input) => {
          calls += 1
          if calls == 1 {
            invalid
          } else {
            assert_true(input.contains("InvalidJoin"))
            assert_true(
              input.contains("{\"via\":\"scans\",\"table\":\"crates\"}"),
            )
            assert_true(input.contains(question))
            replacement
          }
        },
        retry_invalid=true,
      ),
    ) catch {
      @plan.PlanError::InvalidJoin(_, _) => None
      error => raise error
    }
    assert_eq(calls, 2)
    if accepted {
      guard result is Some(Queried(evidence)) else {
        fail("expected query rows")
      }
      assert_eq(evidence.result.rows, [[Text("A17")], [Text("B29")]])
    } else {
      assert_true(result is None)
    }
  }
}
