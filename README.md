# nl2sql

[![ci](https://github.com/young9682/nl2sql.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/young9682/nl2sql.mbt/actions)

Natural language → SQL → read-only execution → evidence-backed answers, as a MoonBit library (native + WASM).

自然语言数据问答引擎：把用户问题变成 SQL，在数据库上**只读**执行，并给出带证据（SQL、行数据、schema）的可解释回答。纯 MoonBit 实现，可编译到原生与 WASM。

> 🚧 **M0 in progress** — the API will change. See the roadmap below.

## Why

- Data Q&A is the most common "read-only analytics" ask for apps and dashboards — most teams just want `SELECT` answers without shipping a SQL client.
- The core (schema model, SQL surface, planning) is **pure MoonBit with zero FFI**, so the same code compiles to native and to a small WASM artifact for browser/edge embedding.
- Every answer carries its evidence: the SQL, the rows, and the schema it ran against.

## Roadmap

- [x] **M0 — Schema model** (this release): `Schema` / `Table` / `Column`, LLM-ready `digest()`, SQLite DDL rendering, JSON output
- [x] **M1 — SQL surface**: read-only gate via token-level validation on the [`moonbit-community/sqlparser`](https://mooncakes.io/docs/moonbit-community/sqlparser) lexer — every statement must start with `SELECT`/`WITH`; full AST validation deferred (see known limitations)
- [ ] **M2 — Execution**: SQLite via [`mizchi/sqlite`](https://mooncakes.io/docs/mizchi/sqlite) (native) / `moonbitstack/moonsqlite` (WASM), read-only mode
- [ ] **M3 — Planning**: natural-language question → SQL plan via [`mizchi/llm`](https://mooncakes.io/docs/mizchi/llm) (OpenAI-compatible, tool calling)
- [ ] **M4 — Answers & CLI**: result → answer with evidence; interactive `cmd/main` CLI

## Quick start

```bash
moon add young9682/nl2sql   # after the first publish
```

```moonbit
let schema = @nl2sql.sample_schema()
println(schema.digest())          // paste into your LLM prompt
println(schema.create_table_sql()) // CREATE TABLE ... statements

let check = @sqlcheck.check_read_only("DELETE FROM users")
// check.ok == false
// check.reason == "statement 1: not a read-only query (starts with Delete)"
```

Run the demo: `moon run cmd/main` · Run tests: `moon test`

## Known limitations (M1)

- **Token-level gate**: `sqlcheck.check_read_only` validates statement *kinds* on the lexer's token stream — every semicolon-separated statement must start with `SELECT` or `WITH`. It does not verify full SQL grammar: a syntactically broken `SELECT` passes the gate and fails later at execution (M2). This keeps the security boundary independent of parser bugs.
- **Upstream parser bug**: `moonbit-community/sqlparser@0.5.2` panics (index out of bounds in `Parser::parse_table_ref`) on any query containing a `FROM <table>` clause, so AST-level validation is deferred until upstream fixes it.

## Design principles

1. **Read-only by construction** — the engine never emits write statements; M1 enforces this at the SQL layer.
2. **Evidence over trust** — an answer without its SQL and rows is a bug, not a feature.
3. **No FFI in the core** — schema model and planning stay pure MoonBit; FFI lives only at the execution edge (M2).

## Development

```bash
moon update        # refresh registry index (fresh checkouts)
moon fmt           # format
moon check         # type check
moon test          # run tests
moon info && moon fmt  # refresh .mbti interfaces
```

## License

Apache-2.0
