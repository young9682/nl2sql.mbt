///|
pub(all) enum CompiledReply {
  Query(CompiledQuery)
  NoAnswer(String)
}

///|
#derive(Debug)
pub suberror ReplyError {
  InvalidReply(String)
}

///|
/// Decodes a structured model reply and checks any plan against the catalog.
/// With resolve_join_path enabled, a rejected plain projection referencing two
/// tables may use a unique shortest declared path of at most two foreign keys.
pub fn compile_reply(
  catalog : @lib.Catalog,
  reply : String,
  resolve_join_path~ : Bool = false,
) -> CompiledReply raise {
  let json = @json.parse(
    reply,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise InvalidReply("expected a single JSON object with unique keys")
  }
  guard json is Object(fields) && fields.length() == 1 else {
    raise InvalidReply("expected a plan or a no-answer reason")
  }
  match (fields.get("plan"), fields.get("no_answer")) {
    (Some(value), None) => {
      normalize_plan_json(value)
      let plan : Plan = @json.from_json(value) catch {
        _ => raise InvalidReply("plan does not match the requested structure")
      }
      let query = compile(catalog, plan) catch {
        InvalidJoin(_, _) as error if resolve_join_path => {
          guard replacement_path(catalog, plan) is Some(joins) else {
            raise error
          }
          compile(catalog, { ..plan, joins, })
        }
        error => raise error
      }
      Query(query)
    }
    (None, Some(String(reason))) if !reason.trim().is_empty() =>
      NoAnswer(reason)
    _ => raise InvalidReply("expected a plan or a no-answer reason")
  }
}

///|
/// Normalizes equivalent spellings in the parsed reply before typed decoding.
fn normalize_plan_json(plan : Json) -> Unit {
  guard plan is Object(fields) else { return }
  if fields.get("limit") is Some(Null) {
    fields.remove("limit")
  }
  guard fields.get("filters") is Some(Array(filters)) else { return }
  for predicate in filters {
    if predicate is Array(parts) &&
      predicate is ["Compare", _, _, ["Real", String(decimal)]] {
      let parsed = @json.parse(decimal, max_nesting_depth=1) catch {
        _ => continue
      }
      if parsed is Number(number, ..) && number.is_finite() {
        parts[3] = ["Real", parsed]
      }
    }
  }
}
