///|
let fixture = "sqlite/fixtures/orders.db"

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
