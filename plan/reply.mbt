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
pub fn compile_reply(
  catalog : @lib.Catalog,
  reply : String,
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
      let plan : Plan = @json.from_json(value) catch {
        _ => raise InvalidReply("plan does not match the requested structure")
      }
      Query(compile(catalog, plan))
    }
    (None, Some(String(reason))) if !reason.trim().is_empty() =>
      NoAnswer(reason)
    _ => raise InvalidReply("expected a plan or a no-answer reason")
  }
}
