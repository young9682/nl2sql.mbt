# nl2sql

[![ci](https://github.com/young9682/nl2sql.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/young9682/nl2sql.mbt/actions)

`nl2sql` is a MoonBit project for answering natural-language questions about SQLite data. The hackathon release targets a native library and CLI that run read-only queries and return answers backed by the executed SQL, result rows, and schema.

参赛版面向本地 SQLite 数据问答，先交付可复用的 MoonBit Native 库和 CLI。回答附带实际执行的 SQL、结果行和 schema。WASM 放在参赛版之后。

> **Current status** — M0 and M1 are complete. The current demo renders a sample schema and shows SQL screening. Native SQLite execution, planning, and answers are planned for M2–M4.

## Why

- Data Q&A is the most common "read-only analytics" ask for apps and dashboards — most teams just want `SELECT` answers without shipping a SQL client.
- The native library gives MoonBit callers the same SQLite execution policy and typed results as the CLI.
- Executed SQL, bound parameters, result rows, and the schema give users a way to check an answer against the database.

## Hackathon roadmap

The submission targets a native SQLite library and CLI. From a clean checkout, a reviewer can follow the README to ask a natural-language question against a bundled SQLite database and verify the answer against the query results. M4 is the submission milestone. The acceptance checks below are project criteria mapped to the event's [completion requirements](https://moonbitlang.github.io/Hackathon2026/#directions) and [quarterly scoring rubric](https://moonbitlang.github.io/Hackathon2026/#quarterly-scoring).

### M0 · Schema model (complete)

- **Deliverables** include `Schema`, `Table`, `Column`, and APIs for schema digests, SQLite DDL, and JSON.
- **Acceptance** requires tests for the sample schema's digest, DDL, and JSON, exact table lookup, and escaping of special characters in JSON.

### M1 · SQL screening (complete)

- **Deliverables** include `sqlcheck.check_read_only` and a CLI demonstration using the `moonbit-community/sqlparser` lexer.
- **Acceptance** requires tests for `SELECT`, CTE queries, and statement splitting, including semicolons inside strings. Empty input and statements beginning with write or DDL keywords must be rejected with a reason. This stage provides the token check described in [Known limitations](#known-limitations-m1).

### M2 · Native SQLite library (planned)

- **Deliverables** include a callable MoonBit query API, a native SQLite adapter, and a bundled `.db` fixture. The API takes one SQL statement and bound parameters and returns ordered columns, typed rows, and truncation status or a structured error. Evaluate `mizchi/sqlite` against the required SQLite APIs and record the driver choice. [Candidate native binding](https://mooncakes.io/docs/mizchi/sqlite)
- **Acceptance** requires a real SQLite file opened read-only and a single prepared query checked by SQLite before execution. Integration tests cover a parameterized `SELECT`, a CTE query, and typed results including `NULL` and 64-bit integers. They also verify rejection of writes (including writes preceded by `WITH`), extra statements, `ATTACH`, and extension loading. Verify that the fixture's data is unchanged after rejection and that timeouts and result truncation are reported explicitly.

### M3 · Structured query planning and evaluation (planned)

- **Deliverables** include a schema description derived from the queried database, including foreign-key relationships, and a typed query plan for table and column selection, joins, filters, grouping, and aggregation. The model returns a structured plan or an explicit no-answer response. MoonBit validates the plan against the actual schema and compiles accepted plans deterministically into parameterized SQLite SQL for the M2 API. Provide an OpenAI-compatible adapter and allow tests to supply deterministic model responses. [Candidate LLM client](https://mooncakes.io/docs/mizchi/llm)
- **Acceptance for planning** requires a parameterized filter and a join with aggregation to return the expected rows. Verify that the same accepted plan and schema produce identical SQL and bindings. Malformed plans, unknown tables or columns, and invalid joins must fail with a structured reason before any data query runs. An explicit no-answer response must also skip data query execution.
- **Evaluation deliverables** include a fixed question set with expected rows or an expected no-answer outcome, a runnable comparison script, and a live-model report with per-question outcomes and aggregate results.
- **Acceptance for evaluation** requires comparing structured planning with direct model-generated SQL on the same questions, database snapshot, schema context, model version, and generation settings. Both paths can abstain and use the same M2 execution policy and limits for queries. Report result accuracy on answerable questions, invalid query or plan rate across the set, and correct abstention on unanswerable questions. Include counts and denominators, rejected cases, and the commands to reproduce the comparison.

### M4 · Evidence-backed answers and native CLI (planned)

- **Deliverables** include a native CLI that accepts a database path and question, a README walkthrough from build to question to evidence, and an integration in a separate MoonBit project that imports the public library API for one of its own workflows. Each successful CLI answer includes the executed SQL, bound parameters, returned rows, and the schema used for planning. Distinguish empty results, truncated output, rejected queries, and execution failures.
- **Acceptance for the CLI** requires a reviewer to reproduce the full workflow with the sample database and deterministic model responses without an API key. Native CI must build the CLI and run the library and CLI integration tests. The repository must include the live-model walkthrough, the M3 comparison report, and an explanation of the execution policy, platform choices, and third-party dependencies, with the work traceable through commits, issues, and PRs.
- **Acceptance for the downstream integration** requires a clean checkout of the separate MoonBit project to build against a documented `nl2sql` version or revision and call the public API directly. Its tests or runnable example must show a successful read with typed results, rejection of a disallowed statement, and explicit handling of a query timeout or result truncation. Include a link to the integration and reproduction commands in this README.

### M5 · WASM deployment (after the hackathon)

- **Deliverables** include a documented target and a SQLite adapter for that target. Evaluate a MoonBit WASM build with host-provided SQLite separately from a MoonBit JS build that loads SQLite WASM.
- **Acceptance** requires a reproducible build and demo on the selected runtime, with the same single-query, read-only, typed-results, timeout, and truncation checks used for the native library.

## Try the current demo

From a checkout, run the schema and SQL screening demo with `moon run cmd/main` and its tests with `moon test`.

After the first package release, add the library to a MoonBit project with the following command.

```bash
moon add young9682/nl2sql
```

```moonbit
let schema = @nl2sql.sample_schema()
println(schema.digest())          // paste into your LLM prompt
println(schema.create_table_sql()) // CREATE TABLE ... statements

let check = @sqlcheck.check_read_only("DELETE FROM users")
// check.ok == false
// check.reason == "statement 1: not a read-only query (starts with Delete)"
```

## Known limitations (M1)

- `sqlcheck.check_read_only` checks the first token of each statement. A malformed `SELECT` can pass, and SQLite allows `WITH` before write operations. M2 enforces the query policy in SQLite. [SQLite WITH clause](https://www.sqlite.org/lang_with.html#overview)
- `moonbit-community/sqlparser@0.5.2` has a known index-out-of-bounds panic in `Parser::parse_table_ref` on queries with `FROM <table>`. M1 uses the lexer while AST-level validation is deferred. [sqlparser package](https://mooncakes.io/docs/moonbit-community/sqlparser)

## Design principles

1. Enforce read-only execution at the SQLite boundary for both the library and CLI.
2. Attach enough evidence to check each successful answer against its query results.
3. Keep the schema model and query planning logic in MoonBit and isolate SQLite FFI in the execution adapter.

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
