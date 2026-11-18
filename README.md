# nl2sql

[![ci](https://github.com/young9682/nl2sql.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/young9682/nl2sql.mbt/actions)

`nl2sql` is a MoonBit project for answering natural-language questions about SQLite data. The hackathon release targets a native library and CLI that run read-only queries and return answers backed by the executed SQL, result rows, and schema.

参赛版面向本地 SQLite 数据问答，先交付可复用的 MoonBit Native 库和 CLI。回答附带实际执行的 SQL、结果行和 schema。参赛版之后的 WASM 演示可在 Node.js 本地复现。

> **Current status** — M0–M2, structured query planning, the comparison runner, and the Native CLI are implemented. The public SQLite API has been verified in a separate MoonBit inventory-report module. M5 has a credential-free Node.js WasmGC demo. The [M3 live-model report](eval/live-model-report.md) records the paired evaluation.

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

### M2 · Native SQLite library (implemented)

- **Deliverables** include a callable MoonBit query API, a native SQLite adapter, and a bundled `.db` fixture. The API takes one SQL statement and bound parameters and returns ordered columns, typed rows, and truncation status or a structured error. The adapter uses SQLite's C API to access statement tails, the authorizer, and the progress handler. These controls are outside the published `mizchi/sqlite` API. [Candidate native binding](https://mooncakes.io/docs/mizchi/sqlite)
- **Acceptance** requires a real SQLite file opened read-only and a single prepared query checked by SQLite before execution. Integration tests cover a parameterized `SELECT`, a CTE query, and typed results including `NULL` and 64-bit integers. They also verify rejection of writes (including writes preceded by `WITH`), extra statements, `ATTACH`, and extension loading. Verify that the fixture's data is unchanged after rejection and that timeouts and result truncation are reported explicitly.

### M3 · Structured query planning and evaluation (complete)

- **Deliverables** include a schema description derived from the queried database, including foreign-key relationships, and a typed query plan for table and column selection, joins, filters, grouping, and aggregation. The model returns a structured plan or an explicit no-answer response. MoonBit validates the plan against the actual schema and compiles accepted plans deterministically into parameterized SQLite SQL for the M2 API. The OpenAI-compatible Chat Completions adapter uses `moonbitlang/async/http`. Tests can supply deterministic model responses. [MoonBit HTTP client](https://mooncakes.io/docs/moonbitlang/async/http)
- **Acceptance for planning** requires a parameterized filter and a join with aggregation to return the expected rows. Verify that the same accepted plan and schema produce identical SQL and bindings. Malformed plans, unknown tables or columns, and invalid joins must fail with a structured reason before any data query runs. An explicit no-answer response must also skip data query execution.
- **Evaluation deliverables** include a fixed question set with expected rows or an expected no-answer outcome, a runnable comparison script, and a live-model report with per-question outcomes and aggregate results.
- **Acceptance for evaluation** requires comparing structured planning with direct model-generated SQL on the same questions, database snapshot, schema context, model version, and generation settings. Both paths can abstain and use the same M2 execution policy and limits for queries. Report result accuracy on answerable questions, invalid query or plan rate across the set, and correct abstention on unanswerable questions. Include counts and denominators, rejected cases, and the commands to reproduce the comparison.

### M4 · Evidence-backed answers and native CLI

- **Deliverables** include a native CLI that accepts a database path and question, a README walkthrough from build to question to evidence, and an integration in a separate MoonBit project that imports the public library API for one of its own workflows. Each successful CLI answer includes the executed SQL, bound parameters, returned rows, and the schema used for planning. Distinguish empty results, truncated output, rejected queries, and execution failures.
- **Acceptance for the CLI** requires a reviewer to reproduce the full workflow with the sample database and deterministic model responses without an API key. Native CI must build the CLI and run the library and CLI integration tests. The repository must include the live-model walkthrough, the M3 comparison report, and an explanation of the execution policy, platform choices, and third-party dependencies, with the work traceable through commits, issues, and PRs.
- **Acceptance for the downstream integration** requires a clean checkout of the separate MoonBit project to build against a documented `nl2sql` version or revision and call the public API directly. Its tests or runnable example must show a successful read with typed results, rejection of a disallowed statement, and explicit handling of a query timeout or result truncation. Include a link to the integration and reproduction commands in this README.

### M5 · WASM deployment (Node.js demo)

- **Deliverables** include a documented target and a SQLite adapter for that target. Evaluate a MoonBit WASM build with host-provided SQLite separately from a MoonBit JS build that loads SQLite WASM.
- **Acceptance** requires a reproducible build and demo on the selected runtime, with the same single-query, read-only, typed-results, timeout, and truncation checks used for the native library.
- **Selected runtime** is Node.js with a MoonBit WasmGC planner and host-provided SQLite WASM. The MoonBit JavaScript build runs against the same SQLite adapter for comparison. The [WASM demo](#wasm-demo) documents both builds and the checks.

## Native CLI demo

From the repository root, run the bundled SQLite demo. It replays a fixed model response and executes the generated read-only query against the sample database, with no endpoint or API key needed.

```bash
moon run --quiet --target native cmd/nl2sql -- --demo
moon run --quiet --target native cmd/nl2sql -- --demo unanswerable-profit
moon run --quiet --target native cmd/nl2sql -- --max-rows 1 --demo spend-by-user
```

The default question asks for each user's total spend. The returned rows show `林` at 50 and `Sam` at 20. The JSON includes the actual `sql`, bound `params`, typed `result` rows, and the schema and foreign keys in `context`. Statuses distinguish successful rows, empty results, truncation, and a no-answer response. Argument and execution errors return an error status and a nonzero exit code.

For a live query, set `NL2SQL_ENDPOINT` to the full Chat Completions URL and `NL2SQL_MODEL` to the model identifier. Set `NL2SQL_API_KEY` when the endpoint requires a bearer token. Then pass an existing SQLite file and the question.

```bash
moon run --quiet --target native cmd/nl2sql -- --db sqlite/fixtures/orders.db "What did each user spend?"
```

Use `--demo CASE_ID` with any ID in the [fixed question set](eval/questions.json), or `--help` for the available options.

## Independent MoonBit integration

The [inventory report](examples/inventory-report/README.md) is a separate MoonBit module that uses `young9682/nl2sql/sqlite` to find low-stock products. Its tests cover typed results, write rejection, and reporting a truncated result as partial. From the repository root, run the following commands.

```bash
cd examples/inventory-report
moon test --target native .
moon run --quiet --target native . -- ../../sqlite/fixtures/orders.db 20 1
```

## WASM demo

From a clean checkout with MoonBit and Node.js 24.2 or later, install the locked SQLite WASM dependency and build the MoonBit planner. Run these commands from the repository root.

```bash
moon update
npm ci --prefix examples/wasm-demo --ignore-scripts
moon build --target wasm-gc --release examples/wasm-demo
node examples/wasm-demo/demo.mjs
node examples/wasm-demo/demo.mjs large-order-id
node examples/wasm-demo/demo.mjs --max-rows 1 spend-by-user
```

The demo uses the fixed model replies from `eval/questions.json` and runs each compiled query against a read-only SQLite snapshot of `sqlite/fixtures/orders.db`. After dependency installation, the demo reads local files and needs no network connection, endpoint, or API key. The default question returns `林` at 50 and `Sam` at 20, plus the executed SQL, parameters, typed rows, and catalog. The large ID is returned as the decimal string `9007199254740993`. A row limit of one produces a `truncated` report.

The Node.js host runs SQLite via [`@sqlite.org/sqlite-wasm`](https://github.com/sqlite/sqlite-wasm) and passes catalog and plan JSON across the [MoonBit WasmGC string interface](https://docs.moonbitlang.com/en/stable/language/ffi.html). SQLite checks the statement tail and authorizes reads, and the adapter uses SQLite's progress handler and elapsed time to interrupt long queries. This deployment covers the bundled local snapshot on Node.js.

To compare MoonBit's JavaScript target with WasmGC, build the same planner package for JavaScript, then run the demo and tests. Both planner builds use the same SQLite WASM host adapter.

```bash
moon build --target js --release examples/wasm-demo
node examples/wasm-demo/demo.mjs --target js
node --test examples/wasm-demo/demo.test.mjs
```

The tests launch the WasmGC demo with model settings unset, compare both builds on all eight fixture questions, and check the SQLite adapter for typed bindings and results, rejection of extra statements and writes, timeout, truncation, and an unchanged snapshot.

## Schema and SQL screening demo

From a checkout, run the schema and SQL screening demo with `moon run cmd/main`. Run the core tests with `moon test --target wasm`.

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

## Native SQLite API

Import `young9682/nl2sql/sqlite` in a Native package. Each `query` call opens its own read-only connection to an existing local SQLite file. The API binds values by SQLite parameter index and returns columns and typed cells in result order.

```moonbit
let result = @sqlite.query(
  "sqlite/fixtures/orders.db",
  "SELECT id, amount FROM orders WHERE user_id = ? ORDER BY id",
  params=[Integer(1L)],
  max_rows=10,
)
```

The default limits are 100 returned rows and five seconds of query work. The SQLite adapter accepts a single read query, applies an authorizer, and blocks attached databases, extension loading, and virtual tables. SQL text is limited to 64 KiB, and SQLite's value/row size limit is 1 MiB. The time limit interrupts SQLite work and is checked between rows. `truncated` is true when an additional row exists beyond the limit.

Use `@sqlite.read_catalog(path)` to inspect the main database's regular tables, columns, and declared foreign keys. The catalog is read in one SQLite statement and preserves composite key order. Catalog inspection requires SQLite 3.37 or later. Linux builds use SQLite development headers and libraries (`libsqlite3-dev` on Ubuntu). Windows uses MSVC and the SDK's `winsqlite3`.

Run `moon test --target native` from the repository root to exercise the fixture. The fixture definition is available in [orders.sql](sqlite/fixtures/orders.sql).

## Compare structured planning with direct SQL

`@planner.ask` takes a database path, a question, and a model callback. The library sends the question, schema, and foreign keys to the model. It validates the returned plan before opening a data query and returns the executed SQL, bindings, rows, and catalog as evidence.

Run the comparison from the repository root.

```bash
moon run --quiet cmd/eval -- --fixture
moon run --quiet cmd/eval -- --live
```

Fixture mode replays checked-in model responses across both paths. Live mode uses `NL2SQL_ENDPOINT` for the full Chat Completions URL, `NL2SQL_MODEL` for the model identifier, and `NL2SQL_API_KEY` when the endpoint requires a bearer token.

Both modes use the bundled SQLite snapshot and [fixed question set](eval/questions.json). The JSON report includes per-question outcomes, executed SQL and parameters for successful queries, result accuracy, invalid output rate, and correct abstention rate. Live mode also records each original model reply. Row comparison preserves duplicates and checks row order when requested. The paired runs, raw output, and reproduction commands are in the [M3 live-model report](eval/live-model-report.md).

## Known limitations (M1)

- `sqlcheck.check_read_only` checks the first token of each statement. A malformed `SELECT` can pass, and SQLite allows `WITH` before write operations. The native query API enforces its policy in SQLite. [SQLite WITH clause](https://www.sqlite.org/lang_with.html#overview)
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
moon test          # run the native SQLite integration and core tests
moon test --target wasm  # run the portable core tests
moon info && moon fmt    # refresh .mbti interfaces
```

## License

Apache-2.0
