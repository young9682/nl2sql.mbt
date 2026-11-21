///|
let usage =
  #|Usage:
  #|  nl2sql [--max-rows N] --demo [CASE_ID]
  #|  nl2sql [--max-rows N] --db PATH "QUESTION"
  #|Demo cases come from eval/questions.json. Run demo mode from the repository root.
  #|Live queries use NL2SQL_ENDPOINT, NL2SQL_MODEL, and optionally NL2SQL_API_KEY.

///|
suberror CliError {
  InvalidArguments(String)
  MissingSetting(String)
  UnknownDemo(String)
}

///|
#derive(FromJson)
struct DemoCase {
  id : String
  question : String
  fixture_plan : Json
}

///|
async fn main {
  let args = @env.args()[1:]
  if args is ["--help"] {
    println(usage)
    return
  }
  let result = run(args) catch {
    error => {
      let (status, detail, code) = describe_error(error)
      let output : Json = {
        "status": Json::string(status),
        "detail": Json::string(detail),
      }
      println(output.stringify(indent=2))
      @env.exit(code)
    }
  }
  println(result.stringify(indent=2))
}

///|
async fn run(args : ArrayView[String]) -> Json {
  let (max_rows, command) = match args {
    ["--max-rows", value, .. rest] => {
      let limit = @string.parse_int(value) catch {
        _ => raise InvalidArguments("--max-rows requires a positive integer")
      }
      if limit <= 0 {
        raise InvalidArguments("--max-rows requires a positive integer")
      }
      (limit, rest)
    }
    _ => (100, args)
  }
  match command {
    ["--demo"] => demo("spend-by-user", max_rows)
    ["--demo", id] => demo(id, max_rows)
    ["--db", path, question] if !question.trim().is_empty() && !path.is_empty() => {
      let endpoint = setting("NL2SQL_ENDPOINT")
      let model = setting("NL2SQL_MODEL")
      let key = @env.get_env_var("NL2SQL_API_KEY").unwrap_or("")
      let generate = @planner.openai_model(endpoint, model, api_key=key)
      let assess = @planner.openai_answerability_model(
        endpoint,
        model,
        api_key=key,
      )
      render_answer(
        question,
        @planner.ask(
          path,
          question,
          generate,
          max_rows~,
          retry_invalid=true,
          assess=Some(assess),
        ),
      )
    }
    _ => raise InvalidArguments(usage)
  }
}

///|
async fn demo(id : String, max_rows : Int32) -> Json {
  let source = @fs.read_file("eval/questions.json").text()
  let cases : Array[DemoCase] = @json.from_json(
    @json.parse(source, reject_duplicate_keys=true),
  )
  for example in cases {
    if example.id == id {
      let reply = example.fixture_plan.stringify()
      let answer = @planner.ask(
        "sqlite/fixtures/orders.db",
        example.question,
        (_, _) => reply,
        max_rows~,
      )
      return render_answer(example.question, answer)
    }
  }
  raise UnknownDemo(id)
}

///|
fn setting(name : String) -> String raise CliError {
  guard @env.get_env_var(name) is Some(value) && !value.trim().is_empty() else {
    raise MissingSetting(name)
  }
  value
}

///|
fn render_answer(question : String, answer : @planner.Answer) -> Json raise {
  match answer {
    NoAnswer(reason) =>
      {
        "status": "no_answer",
        "question": Json::string(question),
        "answer": Json::string(reason),
      }
    Queried(evidence) => {
      let rows = evidence.result.rows.length()
      let (status, summary) = if evidence.result.truncated {
        (
          "truncated",
          "Showing the first \{rows} rows. More rows are available.",
        )
      } else if rows == 0 {
        ("empty", "No rows matched the query.")
      } else {
        ("ok", "The query returned \{rows} row(s).")
      }
      {
        "status": Json::string(status),
        "question": Json::string(question),
        "answer": Json::string(summary),
        "sql": Json::string(evidence.sql),
        "params": @json.to_json(evidence.params),
        "result": @json.to_json(evidence.result),
        "context": @json.parse(@planner.model_input(evidence.catalog, question)),
      }
    }
  }
}

///|
fn describe_error(error : Error) -> (String, String, Int32) {
  match error {
    InvalidArguments(message) => ("invalid_arguments", message, 2)
    UnknownDemo(id) => ("invalid_arguments", "Unknown demo case: \{id}", 2)
    MissingSetting(name) =>
      ("missing_configuration", "Set \{name} for live queries.", 2)
    @plan.PlanError::_ => ("query_rejected", @debug.to_string(error), 1)
    @sqlite.QueryError::Rejected(reason) => ("query_rejected", reason, 1)
    @sqlite.QueryError::TimedOut =>
      ("query_timeout", "SQLite query timed out.", 1)
    @sqlite.QueryError::_ => ("database_error", @debug.to_string(error), 1)
    @planner.PlannerError::InvalidReply(reason) =>
      ("invalid_model_reply", reason, 1)
    @planner.PlannerError::ProviderStatus(code) =>
      ("model_request_failed", "HTTP \{code}", 1)
    @planner.PlannerError::ProviderReply(reason) =>
      ("model_request_failed", reason, 1)
    _ => ("request_failed", "The request could not be completed.", 1)
  }
}
