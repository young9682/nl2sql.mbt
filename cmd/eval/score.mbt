///|
#derive(Eq, ToJson(style="flat"))
enum Outcome {
  CorrectRows
  WrongRows
  CorrectAbstention
  FalseAbstention
  UnexpectedAnswer
  InvalidOutput
  ExecutionFailure
  ProviderFailure
}

///|
struct Observation {
  status : Outcome
  detail : String
  sql : String?
  params : Array[Json]
  rows : Array[Json]?
  truncated : Bool
}

///|
fn Observation::to_json(self : Observation) -> Json {
  let sql = match self.sql {
    Some(sql) => Json::string(sql)
    None => Json::null()
  }
  {
    "status": @json.to_json(self.status),
    "detail": Json::string(self.detail),
    "sql": sql,
    "params": Json::array(self.params),
    "rows": optional_rows(self.rows),
    "truncated": Json::boolean(self.truncated),
  }
}

///|
fn failure(status : Outcome, detail : String) -> Observation {
  { status, detail, sql: None, params: [], rows: None, truncated: false, }
}

///|
fn optional_rows(rows : Array[Json]?) -> Json {
  match rows {
    Some(rows) => Json::array(rows)
    None => Json::null()
  }
}

///|
fn cell_json(cell : @sqlite.Value) -> Json {
  match cell {
    Null => ["Null"]
    Integer(value) => ["Integer", Json::string(value.to_string())]
    Real(value) => ["Real", Json::number(value)]
    Text(value) => ["Text", Json::string(value)]
    Blob(value) => ["Blob", @json.to_json(value.to_array())]
  }
}

///|
fn grade_abstention(question : Case, reason : String) -> Observation {
  let status = if question.expected_rows is Some(_) {
    FalseAbstention
  } else {
    CorrectAbstention
  }
  failure(status, reason)
}

///|
fn grade_rows(
  question : Case,
  sql : String,
  params : Array[@sqlite.Value],
  result : @sqlite.QueryResult,
) -> Observation {
  let rows = result.rows.map(row => Json::array(row.map(cell_json)))
  let status = match question.expected_rows {
    None => UnexpectedAnswer
    Some(expected) =>
      if !result.truncated &&
        rows_match(rows, expected, ordered=question.ordered) {
        CorrectRows
      } else {
        WrongRows
      }
  }
  {
    status,
    detail: if result.truncated {
      "query result was truncated"
    } else {
      ""
    },
    sql: Some(sql),
    params: params.map(cell_json),
    rows: Some(rows),
    truncated: result.truncated,
  }
}

///|
fn rows_match(
  actual : Array[Json],
  expected : Array[Json],
  ordered~ : Bool,
) -> Bool {
  if ordered {
    return actual == expected
  }
  let actual = actual.map(row => row.stringify())
  let expected = expected.map(row => row.stringify())
  actual.sort()
  expected.sort()
  actual == expected
}

///|
fn summarize(
  outcomes : Array[Outcome],
  answerable : Int32,
  unanswerable : Int32,
) -> Json {
  let count = target => outcomes.filter(status => status == target).length()
  {
    "result_accuracy": metric(count(CorrectRows), answerable),
    "invalid_output_rate": metric(count(InvalidOutput), outcomes.length()),
    "correct_abstention_rate": metric(count(CorrectAbstention), unanswerable),
    "provider_failures": Json::number(count(ProviderFailure).to_double()),
    "execution_failures": Json::number(count(ExecutionFailure).to_double()),
  }
}

///|
fn metric(count : Int32, total : Int32) -> Json {
  let rate = if total == 0 {
    Json::null()
  } else {
    Json::number(count.to_double() / total.to_double())
  }
  {
    "count": Json::number(count.to_double()),
    "total": Json::number(total.to_double()),
    "rate": rate,
  }
}
