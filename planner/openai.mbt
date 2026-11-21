///|
/// Creates a model callback for an OpenAI-compatible Chat Completions endpoint.
/// Supply the full endpoint URL. An empty key is useful with local endpoints.
pub fn openai_model(
  endpoint : String,
  model : String,
  api_key~ : String = "",
  request_timeout_ms~ : Int32 = 30000,
) -> async (String, String) -> String {
  openai_chat(endpoint, model, api_key, request_timeout_ms, [])
}

///|
fn openai_chat(
  endpoint : String,
  model : String,
  api_key : String,
  request_timeout_ms : Int32,
  examples : Array[(String, String)],
) -> async (String, String) -> String {
  async fn(system, user) {
    let headers = Map([
      (@http.CaseInsensitiveString("Content-Type"), "application/json"),
    ])
    if !api_key.is_empty() {
      headers[@http.CaseInsensitiveString("Authorization")] = "Bearer " +
        api_key
    }
    let messages : Array[Json] = [
      { "role": "system", "content": Json::string(system) },
    ]
    for (example, reply) in examples {
      messages.push({ "role": "user", "content": Json::string(example) })
      messages.push({ "role": "assistant", "content": Json::string(reply) })
    }
    messages.push({ "role": "user", "content": Json::string(user) })
    let request : Json = {
      "model": Json::string(model),
      "temperature": 0,
      "messages": Json::array(messages),
    }
    let (response, body) = @async.with_timeout(request_timeout_ms, async fn() {
      @http.post(endpoint, request.stringify(), headers~)
    })
    if response.code < 200 || response.code >= 300 {
      raise ProviderStatus(response.code)
    }
    let reply = @json.parse(body.text()) catch {
      _ => raise ProviderReply("provider response is not JSON")
    }
    match reply {
      {
        "choices": [{ "message": { "content": String(content), .. }, .. }, ..],
        ..
      } => content
      _ => raise ProviderReply("provider response has no text choice")
    }
  }
}
