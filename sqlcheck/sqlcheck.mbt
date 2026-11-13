// sqlcheck — the read-only gate for nl2sql.
// Token-level validation on top of moonbit-community/sqlparser's lexer
// (SQLite dialect). Statement-kind checking only needs the first token of
// each semicolon-separated statement: it must be SELECT or WITH.
//
// Why tokens instead of the AST: sqlparser@0.5.2 crashes with an index-out-
// of-bounds in Parser::parse_table_ref on any query containing a
// `FROM <table>` clause, so the AST path is unusable today while the lexer
// is robust. Switch to full AST validation once upstream fixes the parser.

///|
/// The verdict of validating a SQL script against the read-only contract.
pub(all) struct SqlCheck {
  /// `true` only when the script lexed and every statement starts with
  /// `SELECT` or `WITH`.
  ok : Bool
  /// Number of non-empty statements found.
  statements : Int32
  /// Empty when `ok`; otherwise why the script was rejected.
  reason : String
}

///|
/// A short human-readable description of a leading token that caused a
/// rejection.
fn token_desc(t : @sqlparser.Token) -> String {
  match t {
    Keyword(kw) => kw.to_string()
    Identifier(name) => "identifier '\{name}'"
    other => other.to_string()
  }
}

///|
/// Validates that `sql` is a read-only script under the SQLite dialect:
/// every semicolon-separated statement must start with `SELECT` or `WITH`.
/// Anything else — writes, DDL, identifiers, garbage — is rejected with a
/// reason naming the offending statement and token.
///
/// String literals are single tokens, so semicolons inside strings never
/// split a statement.
pub fn check_read_only(sql : String) -> SqlCheck {
  let lexed : Result[Array[@sqlparser.Token], @sqlparser.LexerError] = Ok(
    @sqlparser.tokenize(sql),
  ) catch {
    e => Err(e)
  }
  let toks = match lexed {
    Ok(tokens) => tokens
    Err(e) => return { ok: false, statements: 0, reason: "lex error: \{e}", }
  }
  let n = toks.length()
  let mut count = 0
  let mut start = 0
  let mut idx = 0
  while idx <= n {
    if idx == n || toks[idx] is Semicolon {
      if idx > start {
        count = count + 1
        match toks[start] {
          Keyword(kw) =>
            match kw {
              Select | With => ()
              _ =>
                return {
                  ok: false,
                  statements: count,
                  reason: "statement \{count}: not a read-only query (starts with \{kw.to_string()})",
                }
            }
          t =>
            return {
              ok: false,
              statements: count,
              reason: "statement \{count}: not a read-only query (starts with \{token_desc(t)})",
            }
        }
      }
      start = idx + 1
    }
    idx = idx + 1
  }
  if count == 0 {
    return { ok: false, statements: 0, reason: "no statements", }
  }
  { ok: true, statements: count, reason: "", }
}
