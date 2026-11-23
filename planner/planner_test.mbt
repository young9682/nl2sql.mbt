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
    let contradictory =
      #|{"no_answer":"The 'amount' column is missing in the 'ORDERS' table."}
    let genuine_missing =
      #|{"no_answer":"The 'logins' column is missing in the 'users' table."}
    let row_claim =
      #|{"no_answer":"No order has the requested amount."}
    let review_refusal = "{\"missing_column\":[\"orders\",\"contract_rate\"]}"
    group.spawn_bg(() => {
      for
        (review, reply) in [
          (false, initial_refusal),
          (false, genuine_missing),
          (false, row_claim),
          (false, "{\"supported\":true}"),
          (true, review_refusal),
          (false, contradictory),
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
    assert_eq(assess(catalog, "When did each user log in?"), genuine_missing)
    assert_eq(
      assess(catalog, "Which order has the requested amount?"),
      row_claim,
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
  let missing_bridge = valid.replace_all(
    old="{\"table\":\"crates\",\"via\":\"scans\"},{\"table\":\"bays\",\"via\":\"crates\"}",
    new="{\"table\":\"bays\",\"via\":\"scans\"}",
  )
  for
    (accepted, replacement) in [
      (true, valid),
      (true, missing_bridge),
      (false, invalid),
    ] {
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

///|
let tool_prices =
  #|{"plan":{"from_table":"tools","select":[["Column",{"table":"tools","column":"price"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}

///|
async test "text filter review preserves negative, alternative and partial matches" {
  let catalog = @sqlite.read_catalog("eval/filter-dev/tools.db")
  let controls = [
    "List prices for tools other than planes.", "List prices for tools that aren't planes.",
    "返回除刨子以外工具的价格。", "Give prices for either saws or chisels.",
    "Give prices for one of these categories: saw, chisel.", "列出锯子或凿子的价格。",
    "Show prices where the label contains Copper.", "Show prices for labels starting with Copper.",
    "Give prices for labels that end with Finch.", "返回标签以 Copper 开头的工具价格。",
    "找出标签包含 Copper 的工具价格。",
  ]
  for question in controls {
    let (effective, review) = @planner.review_text_filter(
      catalog,
      question,
      tool_prices,
      _ => fail("unexpected equality review for " + question),
    )
    assert_eq(effective, tool_prices)
    assert_eq(review, None)
  }
}

///|
async test "text filter review binds a grounded value and preserves unconfirmed plans" {
  let db = "eval/filter-dev/tools.db"
  let catalog = @sqlite.read_catalog(db)
  let reply =
    #|{"equals":["category","chisel"]}
  let question = "List the prices of the chisels."
  let answer = @planner.ask(
    db,
    question,
    (_, _) => tool_prices,
    review_filter=Some(input => {
      assert_true(input.contains("text_columns"))
      assert_false(input.contains("return_column"))
      reply
    }),
  )
  guard answer is Queried(evidence) else { fail("expected executed plan") }
  assert_eq(evidence.params, [Text("chisel")])
  assert_eq(evidence.result.rows, [[Integer(12L)], [Integer(12L)]])
  for
    (q, proposal) in [
      (question, "{\"equals\":null}"),
      ("Show each tool label.", "{\"equals\":[\"label\",\"label\"]}"),
      (question, "{\"equals\":[\"category\",\"plane\"]}"),
      (question, "{\"equals\":[\"category\",\"his\"]}"),
      (question, "{\"equals\":[\"price\",\"chisel\"]}"),
      (question, "{\"equals\":[\"category\",\"chisel\"],\"else\":true}"),
      ("Give prices for 'Copper Finch'.", "{\"equals\":[\"label\",\"Copper\"]}"),
    ] {
    let (effective, raw) = @planner.review_text_filter(
      catalog,
      q,
      tool_prices,
      _ => proposal,
    )
    assert_eq(effective, tool_prices)
    assert_eq(raw, Some(proposal))
  }
}

///|
async test "review skips filtered, grouped, joined, invalid and refused first replies" {
  let catalog = @sqlite.read_catalog("eval/filter-dev/tools.db")
  let filtered = tool_prices.replace_all(
    old="\"filters\":[]",
    new="\"filters\":[[\"IsNull\",{\"table\":\"tools\",\"column\":\"maker\"}]]",
  )
  let grouped = tool_prices.replace_all(
    old="\"group_by\":[]",
    new="\"group_by\":[{\"table\":\"tools\",\"column\":\"price\"}]",
  )
  let joined = tool_prices.replace_all(
    old="\"joins\":[]",
    new="\"joins\":[{\"via\":\"tools\",\"table\":\"vendors\"}]",
  )
  let invalid = tool_prices.replace_all(
    old="\"column\":\"price\"",
    new="\"column\":\"unknown\"",
  )
  for
    first in [
      filtered, grouped, joined, invalid, "{\"no_answer\":\"missing facts\"}",
    ] {
    let (effective, raw) = @planner.review_text_filter(
      catalog,
      "List prices for planes.",
      first,
      _ => fail("unexpected review"),
    )
    assert_eq(effective, first)
    assert_eq(raw, None)
  }
}

///|
async test "calendar review distinguishes the returned column from the bound literal" {
  let db = "eval/binding-dev/calendar.db"
  let catalog = @sqlite.read_catalog(db)
  let literal = "2025-02-14"
  for
    (output, column, question, expected) in [
      (
        "published_on",
        "label",
        "When was the release labeled \"2025-02-14\" published?",
        ["2025-08-19"],
      ),
      (
        "label",
        "published_on",
        "Give the release labels published on 2025-02-14.",
        ["June Parade", "Saffron Kite"],
      ),
    ] {
    let first =
      $|{"plan":{"from_table":"releases","select":[["Column",{"table":"releases","column":"\{output}"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}
    let proposal =
      $|{"equals":["\{column}","\{literal}"]}
    let (effective, raw) = @planner.review_text_filter(
      catalog,
      question,
      first,
      input => {
        let context = @json.parse(input)
        guard context
          is {
            "return_column": String(returned),
            "question": String(asked),
            ..
          } else {
          fail("missing projection context")
        }
        assert_eq(returned, output)
        assert_eq(asked, question)
        proposal
      },
    )
    assert_eq(raw, Some(proposal))
    guard @planner.execute_reply(db, catalog, effective) is Queried(result) else {
      fail("expected a calendar query")
    }
    assert_eq(result.params, [Text(literal)])
    // SQL row order is unspecified for both lookups.
    assert_eq(result.result.rows.length(), expected.length())
    for value in expected {
      assert_true(result.result.rows.contains([Text(value)]))
    }
  }
}

///|
async test "date projection skips equality for negation, alternatives and partial names" {
  let catalog = @sqlite.read_catalog("eval/binding-dev/calendar.db")
  let first =
    #|{"plan":{"from_table":"meetups","select":[["Column",{"table":"meetups","column":"held_on"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}
  for
    question in [
      "Give dates for meetups other than Cloud Circle.", "When was either Cloud Circle or Signal Walk held?",
      "List dates for meetup names containing Cloud.", "列出除 Cloud Circle 以外的活动日期。",
      "列出 Cloud Circle 或 Signal Walk 的活动日期。", "列出名称以 Cloud 开头的活动日期。",
    ] {
    let (effective, raw) = @planner.review_text_filter(
      catalog,
      question,
      first,
      _ => fail("unexpected equality review for " + question),
    )
    assert_eq(effective, first)
    assert_eq(raw, None)
  }
}

///|
async test "per-row category filter preserves duplicate weights across matching parcels" {
  let db = "eval/category-dev/parcels.db"
  let catalog = @sqlite.read_catalog(db)
  let first =
    #|{"plan":{"from_table":"parcels","select":[["Column",{"table":"parcels","column":"mass_g"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}
  let proposal =
    #|{"equals":["shape","tube"]}
  let (effective, raw) = @planner.review_text_filter(
    catalog,
    "Give the masses of the tubes, one result per parcel.",
    first,
    input => {
      assert_true(@json.parse(input) is { "individual_rows": true, .. })
      proposal
    },
  )
  assert_eq(raw, Some(proposal))
  guard @planner.execute_reply(db, catalog, effective) is Queried(result) else {
    fail("expected a per-parcel query")
  }
  assert_eq(result.params, [Text("tube")])
  let rows = result.result.rows
  assert_eq(rows.length(), 3)
  assert_eq(rows.filter(row => row == [Integer(420L)]).length(), 2)
  assert_eq(rows.filter(row => row == [Integer(630L)]).length(), 1)
  let pouch =
    #|{"equals":["shape","pouch"]}
  let propose_pouch : async (String) -> String = _ => pouch
  for
    (question, accepted) in [
      ("What are the masses of the pouches?", true),
      ("What are the masses of the pouch?", true),
      ("What are the masses of the pouchesXYZ?", false),
      ("What are the masses of the repouches?", false),
      ("Give the mass recorded for 'pouches'.", false),
    ] {
    let (reviewed, _) = @planner.review_text_filter(
      catalog, question, first, propose_pouch,
    )
    assert_eq(reviewed != first, accepted)
  }
}

///|
async test "aggregate equality review keeps its own context" {
  let catalog = @sqlite.read_catalog("eval/category-dev/parcels.db")
  let first =
    #|{"plan":{"from_table":"parcels","select":[["Max",{"table":"parcels","column":"mass_g"}]],"joins":[],"filters":[],"group_by":[],"order_by":[]}}
  let proposal =
    #|{"equals":null}
  let (effective, raw) = @planner.review_text_filter(
    catalog,
    "What is the highest mass across all parcels?",
    first,
    input => {
      assert_false(input.contains("individual_rows"))
      proposal
    },
  )
  assert_eq(effective, first)
  assert_eq(raw, Some(proposal))
}

///|
test "party examples respect catalog roles, missing parties and unrelated questions" {
  let catalog = @sqlite.read_catalog("eval/borrower-dev/scores.db")
  let borrower = @planner.plan_prompt_for(
    catalog, "Which titles were borrowed by Cedar Choir?",
  )
  let lender = @planner.plan_prompt_for(
    catalog, "List the titles supplied by Cedar Choir.",
  )
  assert_true(borrower.contains("matching text role in this schema is renter."))
  assert_true(lender.contains("matching text role in this schema is lender."))
  for
    question in [
      "List score titles for checkouts with no recorded renter.", "Find titles borrowed by nobody.",
      "Find titles not borrowed by Cedar Choir.", "Find titles rented by Cedar Choir or Wind Studio.",
      "Find titles supplied by Cedar Choir and requested by Wind Studio.", "List every score title, ordered by title.",
    ] {
    assert_eq(@planner.plan_prompt_for(catalog, question), @planner.plan_prompt)
  }
  let mixed : @lib.Catalog = {
    schema: @lib.Schema::new([
      @lib.Table::new("bookings", [
        @lib.Column::new("Renter", "TEXT"),
        @lib.Column::new("customer", "INTEGER"),
      ]),
    ]),
    foreign_keys: [],
  }
  let question = "Give titles requested by Cedar Choir."
  assert_true(
    @planner.plan_prompt_for(mixed, question).contains(
      "in this schema is Renter.",
    ),
  )
  let ambiguous : @lib.Catalog = {
    ..mixed,
    schema: @lib.Schema::new(
      mixed.schema.tables +
      [@lib.Table::new("payments", [@lib.Column::new("customer", "TEXT")])],
    ),
  }
  assert_false(
    @planner.plan_prompt_for(ambiguous, question).contains(
      "matching text role in this schema",
    ),
  )
}

///|
async test "named checkout carries its role through a retry and returns only titles" {
  let db = "eval/borrower-dev/scores.db"
  let question = "Give the score titles requested by Cedar Choir."
  let valid =
    #|{"plan":{"from_table":"checkouts","select":[["Column",{"table":"scores","column":"title"}]],"joins":[{"table":"scores","via":"checkouts"}],"filters":[["Compare",{"table":"checkouts","column":"renter"},"Equal",["Text","Cedar Choir"]]],"group_by":[],"order_by":[]}}
  let mut calls = 0
  let result = @planner.ask(
    db,
    question,
    (system, input) => {
      assert_true(
        system.contains("matching text role in this schema is renter."),
      )
      assert_true(input.contains(question))
      calls += 1
      if calls == 1 {
        "{}"
      } else {
        valid
      }
    },
    retry_invalid=true,
  )
  guard result is Queried(evidence) else { fail("expected a score lookup") }
  assert_eq(calls, 2)
  assert_eq(evidence.params, [Text("Cedar Choir")])
  assert_eq(evidence.result.columns, ["title"])
  assert_eq(evidence.result.rows.length(), 3)
  assert_eq(
    evidence.result.rows.filter(row => row == [Text("Fir Waltz")]).length(),
    2,
  )
  assert_true(evidence.result.rows.contains([Text("Rain Canon")]))
}

///|
test "dated transaction prompts bind the named party and the inclusive date separately" {
  let catalog = @sqlite.read_catalog("eval/range-dev/bookings.db")
  let prompt = @planner.plan_prompt_for(
    catalog, "List the booking dates of reservations for Iris Studio from March 10, 2025 onward.",
  )
  assert_true(prompt.contains("GreaterEqual [\"Text\",\"2025-03-10\"]"))
  assert_true(
    prompt.contains(
      "[\"Compare\",{\"table\":\"bookings\",\"column\":\"customer\"},\"Equal\",[\"Text\",\"Iris Studio\"]]",
    ),
    msg=prompt,
  )
}

///|
test "date range hints distinguish inclusive and exclusive bounds and skip compound dates" {
  let catalog = @sqlite.read_catalog("eval/range-dev/bookings.db")
  for
    (question, expected) in [
      (
        "List booking dates after 2024-02-29.", "Greater [\"Text\",\"2024-02-29\"]",
      ),
      (
        "List booking dates before April 1, 2025.", "Less [\"Text\",\"2025-04-01\"]",
      ),
      (
        "Give booking dates on or before 2025-03-08.", "LessEqual [\"Text\",\"2025-03-08\"]",
      ),
      (
        "List booking dates on or after March 10 2025.", "GreaterEqual [\"Text\",\"2025-03-10\"]",
      ),
    ] {
    let prompt = @planner.plan_prompt_for(catalog, question)
    assert_true(prompt.contains(expected))
    assert_false(prompt.contains("Additional required Compare predicate"))
  }
  for
    question in [
      "Show booking dates not after March 10, 2025.", "Show booking dates after March 3, 2025 and before March 10, 2025.",
      "Show booking dates before 2025-02-29.", "Show booking dates after April 31, 2025.",
      "Show booking dates from Birch Hall.", "Show delivery times after shipping costs.",
    ] {
    assert_eq(@planner.plan_prompt_for(catalog, question), @planner.plan_prompt)
  }
  let party = @planner.plan_prompt_for(
    catalog, "List booking dates supplied by Iris Studio from 2025-03-10 onwards.",
  )
  assert_true(party.contains("\"column\":\"provider\""))
  let item = @planner.plan_prompt_for(
    catalog, "List booking dates of exhibits for Silver Oak from 2025-03-10 onward.",
  )
  assert_false(item.contains("Additional required Compare predicate"))
}

///|
test "implicit receiving-party hints keep the original literal and role" {
  let catalog = @sqlite.read_catalog("eval/party-dev/rentals.db")
  let predicate =
    #|["Compare",{"table":"rentals","column":"renter"},"Equal",["Text","Amber Guild"]]
  for
    question in [
      "List the rental dates for Amber Guild.", "List the items of rentals for Amber Guild.",
      "List the rental dates for \"Amber Guild\".",
    ] {
    assert_true(@planner.plan_prompt_for(catalog, question).contains(predicate))
  }
  for
    question in [
      "Give the rental dates for tripods.", "Give the rental dates for Amber Guild or Cedar Hall.",
      "Give rental dates for equipment named Amber Guild.", "Give rental dates for Amber Guild, excluding tripods.",
      "Give rental dates with no recorded renter.",
    ] {
    assert_eq(@planner.plan_prompt_for(catalog, question), @planner.plan_prompt)
  }
  let supplier = @planner.plan_prompt_for(
    catalog, "List rental dates supplied by Amber Guild.",
  )
  assert_true(supplier.contains("matching text role in this schema is owner."))
  let ambiguous : @lib.Catalog = {
    ..catalog,
    schema: @lib.Schema::new(
      catalog.schema.tables +
      [@lib.Table::new("orders", [@lib.Column::new("customer", "TEXT")])],
    ),
  }
  assert_eq(
    @planner.plan_prompt_for(ambiguous, "List rental dates for Amber Guild."),
    @planner.plan_prompt,
  )
}
