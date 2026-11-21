# nl2sql

[![ci](https://github.com/young9682/nl2sql.mbt/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/young9682/nl2sql.mbt/actions/workflows/ci.yml?query=branch%3Amain)

`nl2sql` is a MoonBit library and Native CLI for asking natural-language questions about local SQLite data. It validates a structured query plan against the database catalog, compiles it to parameterized SQL, and returns the executed SQL, bindings, and typed rows as evidence.

项目已通过申报审核，当前以 Native SQLite 库和 CLI 为主要验收路径。评委可从 [无密钥演示](#native-cli-demo) 开始，核对执行结果，再查看 [下游接入](#independent-moonbit-integration) 和 [真实模型评测](#compare-structured-planning-with-direct-sql)。WASM 扩展演示在 Node.js 上运行。

## Native CLI demo

Use the MoonBit compiler `v0.10.20+65efd5b93` used by CI. On Ubuntu, install a C compiler, `libsqlite3-dev`, and `libssl-dev`. On Windows, install the MSVC C++ build tools and Windows SDK. Catalog inspection requires SQLite 3.37 or later.

From a fresh checkout, run the commands below from the repository root. After the dependencies resolve, the demo replays a fixed model reply and executes a real read-only query on the bundled SQLite database without an endpoint or API key.

```bash
moon update
moon run --quiet --target native cmd/nl2sql -- --demo
```

The JSON includes the executed `sql`, bound `params`, typed `result` rows, and the schema and foreign keys in `context`. Use the arguments below after the `--` separator to check the main result states.

| Arguments | Status | Expected result |
| --- | --- | --- |
| `--demo` | `ok` | Total spend for `林` is 50 and for `Sam` is 20. |
| `--demo empty-dataset-result` | `empty` | No order amount exceeds 1000. |
| `--max-rows 1 --demo spend-by-user` | `truncated` | One row for `林`, with `result.truncated` set to `true`. |
| `--demo unanswerable-profit` | `no_answer` | The replayed reply explains that the database lacks costs. |

Argument and execution errors return an error status and a nonzero exit code. Use `--demo CASE_ID` with any ID in the fixed question set. [Fixture questions and expected rows](eval/questions.json)

### Live queries

Set `NL2SQL_ENDPOINT` to the full Chat Completions URL, `NL2SQL_MODEL` to the model identifier, and `NL2SQL_API_KEY` if the endpoint requires a bearer token. Pass an existing SQLite file and a question.

```bash
moon run --quiet --target native cmd/nl2sql -- --db sqlite/fixtures/orders.db "What did each user spend?"
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

## Independent MoonBit integration

The inventory report is a separate MoonBit module that imports `young9682/nl2sql/sqlite` to find low-stock products. With the Native CLI prerequisites and Python 3 installed, run the same verification as CI from the repository root. [Native CLI prerequisites](#native-cli-demo)

```bash
moon update
python3 examples/inventory-report/verify.py
```

On Windows, use `python` if that is your Python 3 command. The verifier builds the inventory module in a temporary workspace against the current `nl2sql` revision. Its three tests cover typed results, write rejection, and truncation. It runs the sample with model settings cleared, checks for `partial` with an integer quantity of 5 for `Tea` in `east`, and verifies that the SQLite copy stays byte-for-byte identical. [Module and workspace setup](examples/inventory-report/README.md)

### User-directory audit in sqlc_gen_moonbit

The public fork of `mizchi/sqlc_gen_moonbit` runs the original Native SQLite workflow to create Alice and Bob, update Alice, and delete Bob. It then audits the resulting database through the public `young9682/nl2sql/planner` API at revision `af0c79c7f516dfb9da2e8c08d0a7cc67254c8b2d`. The audit binds the SQLite integer `1`, returns only Alice Smith (ID 1), and verifies that the database SHA-256 matches before and after the query.

Reproduce on Windows with PowerShell 7.4 or later, Git, MoonBit compiler `v0.10.20+65efd5b93`, MSVC, and the Windows SDK. Set `-SqliteSdk` to a directory containing `include/sqlite3.h`, `lib/sqlite3.lib`, and `bin/sqlite3.dll`. The verifier uses a fixed model reply and needs no API key.

```powershell
git clone https://github.com/young9682/sqlc_gen_moonbit.git
cd sqlc_gen_moonbit
git checkout --detach d4c44ca0105d4c176a3875628669e74dddcad230
./examples/sqlite_native/verify-nl2sql.ps1 -SqliteSdk 'C:\path\to\environment\Library'
```

The verifier prints the paths to both reports. `audit-result.json` records the executed SQL, bindings, and typed rows. `audit-verification.json` records the dependency revision and both checksums. [Fork audit notes](https://github.com/young9682/sqlc_gen_moonbit/blob/d4c44ca0105d4c176a3875628669e74dddcad230/examples/sqlite_native/NL2SQL-AUDIT.md) · [Recorded query and rows](https://github.com/young9682/sqlc_gen_moonbit/blob/d4c44ca0105d4c176a3875628669e74dddcad230/examples/sqlite_native/audit-result.json) · [Recorded revision and checksums](https://github.com/young9682/sqlc_gen_moonbit/blob/d4c44ca0105d4c176a3875628669e74dddcad230/examples/sqlite_native/audit-verification.json)

## Compare structured planning with direct SQL

`@planner.ask` takes a database path, a question, and a model callback. The library sends the question, schema, and foreign keys to the model. It validates the returned plan before opening a data query and returns the executed SQL, bindings, rows, and catalog as evidence.

The reply decoder treats `"limit": null` as an omitted limit and accepts a quoted JSON number for a `Real` filter if the parsed value is finite.

The latest live-model follow-up uses Qwen2.5-Coder 1.5B and the same eight questions, SQLite snapshot, and JSON grammar for both paths. Repeated runs produced identical reports.

| Metric | Structured plan before update | Structured plan after update | Direct SQL |
| --- | ---: | ---: | ---: |
| Correct results on answerable questions | 0/6 | 3/6 | 4/6 |
| Invalid output across all questions | 8/8 | 4/8 | 2/8 |
| Correct abstention on unanswerable questions | 0/2 | 0/2 | 0/2 |

These results describe the tested model and question set. The report records the rejected plans, an executable query that returned the wrong rows, and reproduction steps. [Planner follow-up](eval/live-model-report.md#follow-up-with-plan-examples-and-compatible-replies)

Run the comparison from the repository root.

```bash
moon run --quiet --target native cmd/eval -- --fixture
moon run --quiet --target native cmd/eval -- --live
```

Fixture mode replays checked-in model responses across both paths. Live mode uses `NL2SQL_ENDPOINT` for the full Chat Completions URL, `NL2SQL_MODEL` for the model identifier, and `NL2SQL_API_KEY` when the endpoint requires a bearer token.

Both modes use the bundled SQLite snapshot and [fixed question set](eval/questions.json). The JSON report includes per-question outcomes, executed SQL and parameters for successful queries, result accuracy, invalid output rate, and correct abstention rate. Live mode also records each original model reply. Row comparison preserves duplicates and checks row order when requested. The paired runs, raw output, and reproduction commands are in the [M3 live-model report](eval/live-model-report.md).

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

## Known limitations (M1)

- `sqlcheck.check_read_only` checks the first token of each statement. A malformed `SELECT` can pass, and SQLite allows `WITH` before write operations. The native query API enforces its policy in SQLite. [SQLite WITH clause](https://www.sqlite.org/lang_with.html#overview)
- `moonbit-community/sqlparser@0.5.2` has a known index-out-of-bounds panic in `Parser::parse_table_ref` on queries with `FROM <table>`. M1 uses the lexer while AST-level validation is deferred. [sqlparser package](https://mooncakes.io/docs/moonbit-community/sqlparser)

## Design principles

1. Enforce read-only execution at the SQLite boundary for both the library and CLI.
2. Attach enough evidence to check each successful answer against its query results.
3. Keep the schema model and query planning logic in MoonBit and isolate SQLite FFI in the execution adapter.

## Hackathon roadmap

M4 defines the Native acceptance scope and M5 covers the Node.js WASM extension. The checks below are project criteria mapped to the event's completion requirements and quarterly scoring rubric. [Completion requirements](https://moonbitlang.github.io/Hackathon2026/#directions) · [Quarterly scoring rubric](https://moonbitlang.github.io/Hackathon2026/#quarterly-scoring)

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

### M4 · Evidence-backed answers and native CLI (verified)

- **Deliverables** include a native CLI that accepts a database path and question, a README walkthrough from build to question to evidence, and an integration in a separate MoonBit project that imports the public library API for one of its own workflows. Each successful CLI answer includes the executed SQL, bound parameters, returned rows, and the schema used for planning. Distinguish empty results, truncated output, rejected queries, and execution failures.
- **Acceptance for the CLI** requires a reviewer to reproduce the full workflow with the sample database and deterministic model responses without an API key. Native CI must build the CLI and run the library and CLI integration tests. The repository must include the live-model walkthrough, the M3 comparison report, and an explanation of the execution policy, platform choices, and third-party dependencies, with the work traceable through commits, issues, and PRs.
- **Acceptance for the downstream integration** requires a clean checkout of the separate MoonBit project to build against a documented `nl2sql` version or revision and call the public API directly. Its tests or runnable example must show a successful read with typed results, rejection of a disallowed statement, and explicit handling of a query timeout or result truncation. CI runs the isolated workspace check against the checked-out revision. [Integration and reproduction commands](#independent-moonbit-integration)

### M5 · WASM deployment (Node.js demo)

- **Deliverables** include a documented target and a SQLite adapter for that target. Evaluate a MoonBit WASM build with host-provided SQLite separately from a MoonBit JS build that loads SQLite WASM.
- **Acceptance** requires a reproducible build and demo on the selected runtime, with the same single-query, read-only, typed-results, timeout, and truncation checks used for the native library.
- **Selected runtime** is Node.js with a MoonBit WasmGC planner and host-provided SQLite WASM. The MoonBit JavaScript build runs against the same SQLite adapter for comparison. The [WASM demo](#wasm-demo) documents both builds and the checks.

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
