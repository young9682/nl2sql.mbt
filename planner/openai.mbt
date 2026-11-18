///|
/// Creates a model callback for an OpenAI-compatible Chat Completions endpoint.
/// Supply the full endpoint URL. An empty key is useful with local endpoints.
pub fn openai_model(
  endpoint : String,
  model : String,
  api_key~ : String = "",
  request_timeout_ms~ : Int32 = 30000,
) -> async (String, String) -> String {
  async fn(system, user) {
    let headers = Map([
      (@http.CaseInsensitiveString("Content-Type"), "application/json"),
    ])
    if !api_key.is_empty() {
      headers[@http.CaseInsensitiveString("Authorization")] = "Bearer " +
        api_key
    }
    let request : Json = {
      "model": Json::string(model),
      "temperature": 0,
      "messages": [
        { "role": "system", "content": Json::string(system) },
        { "role": "user", "content": Json::string(user) },
      ],
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
