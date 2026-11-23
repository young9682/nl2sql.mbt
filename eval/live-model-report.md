# M3 real-model comparison

## Setup

On 2026-11-18, the evaluator ran the [eight fixed questions](questions.json) against the [bundled SQLite database](../sqlite/fixtures/orders.db). Six questions are answerable, including one with an empty result, and two require abstention. The evaluator makes one request per path per question. Both paths use the same model, generation settings, database snapshot, question text, schema, and foreign keys.

- The **structured plan** path asks for a JSON plan or a no-answer reason. MoonBit validates the plan against the database catalog and compiles it into SQL with bound parameters. [Planner prompt and execution](../planner/planner.mbt)
- The **direct SQL** path asks for a JSON object containing one read-only SQLite query or a no-answer reason. [Direct SQL prompt and evaluator](../cmd/eval/main.mbt)

Both paths run queries through the Native SQLite adapter with a 100-row limit and a 5-second query timeout. The model request timeout is 30 seconds on either path. Scoring compares typed rows, preserving duplicates and enforcing row order only where the question set specifies it. An empty result counts as a correct answer when the expected result is empty. Abstention is scored separately.

## Results

| Generation setting | Metric | Structured plan | Direct SQL |
| --- | --- | ---: | ---: |
| Prompts only | Result accuracy | 0/6 (0%) | 0/6 (0%) |
| Prompts only | Invalid output | 8/8 (100%) | 8/8 (100%) |
| Prompts only | Correct abstention | 0/2 (0%) | 0/2 (0%) |
| Same JSON grammar on both paths | Result accuracy | 0/6 (0%) | 4/6 (66.7%) |
| Same JSON grammar on both paths | Invalid output | 8/8 (100%) | 2/8 (25%) |
| Same JSON grammar on both paths | Correct abstention | 0/2 (0%) | 0/2 (0%) |

In the prompts-only run, all 16 responses began with a Markdown code fence and failed strict JSON parsing before any data query ran. The follow-up applied the same generic JSON object grammar to both paths. The grammar constrains syntax during generation. The evaluator still applies its original plan decoder, catalog checks, SQLite policy, and row scoring. Each setting produced identical output on a repeat run, with zero provider failures and zero execution failures. The raw reports retain each original model reply, status, and any executed SQL and rows. [Prompts-only JSON](results/qwen2.5-coder-1.5b-prompt-only.json) · [JSON grammar results](results/qwen2.5-coder-1.5b-json-grammar.json)

| Question | Structured plan with JSON grammar | Direct SQL with JSON grammar |
| --- | --- | --- |
| `large-order-id` | Rejected reply | Correct. Preserved the 64-bit order ID. |
| `spend-by-user` | Rejected reply | Wrong rows. Added `LIMIT 1` and omitted Sam. |
| `top-stock` | Rejected reply | Rejected SQL. Referenced `T1.title` through the stock table alias. |
| `missing-note-count` | Rejected reply | Correct count of one. |
| `empty-dataset-result` | Rejected reply | Correct empty result. |
| `stock-by-region` | Rejected reply | Correct totals. |
| `unanswerable-profit` | Rejected reply | Returned a user based on gross spend despite missing cost data. |
| `unanswerable-delivery-date` | Rejected reply | Rejected SQL. Referenced nonexistent `orders.created_at`. |

With the generic JSON grammar, four structured replies still failed strict JSON decoding and four parsed as JSON but did not match the plan structure. The model used arrays where the contract requires an object and SQL expressions where it requires typed projections. An invalid reply on an unanswerable question counts as invalid output and does not earn abstention credit. The figures describe eight questions on one small, quantized model and one pair of prompts.

## Reproduce

- Evaluator revision `d9c5f304202df6f84a1f3298bac49f257dccf0f7`, MoonBit compiler `v0.10.20+65efd5b93`, Windows SQLite `3.43.2`. [SQLite execution adapter](../sqlite/sqlite.c)
- Model `Qwen2.5-Coder-1.5B-Instruct`, official GGUF quantized as `Q4_K_M`, upstream revision `f86cb2c1fa58255f8052cc32aeede1b7482d4361`. GGUF SHA-256 `cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046`. [Pinned model file](https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/blob/f86cb2c1fa58255f8052cc32aeede1b7482d4361/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf)
- Runtime `llama.cpp b12503` (`4577932fa`), Windows x64 Vulkan on a GeForce RTX 5060 Laptop GPU. [Runtime release](https://github.com/ggml-org/llama.cpp/releases/tag/b12503)
- Dataset Git blobs `4910311e2e4c6af478adb2b749ff7a5c08d77f86` for `eval/questions.json` and `8e8da6b9ea3c6723bbef3cc47683e5f2ba43501a` for `sqlite/fixtures/orders.db`. Database SHA-256 `4462cefb2d3445318110997f66f942a7270e195bc411a5ecab04ee239adeecba`.

Download the pinned GGUF and extract the Windows Vulkan release. In PowerShell 7.4 or later, run the following from the directory containing the weights and put `llama-server.exe` on your path. Use `llama-server --list-devices` to identify the Vulkan device on your machine. Both paths use greedy decoding at temperature 0 and seed 42. The server uses a 4,096-token context and is launched with `--predict 512`.

```powershell
$weights = (Resolve-Path .\qwen2.5-coder-1.5b-instruct-q4_k_m.gguf).Path
Get-FileHash $weights -Algorithm SHA256
$serverArgs = @(
  '--model', $weights, '--alias', 'qwen2.5-coder-1.5b-instruct-q4_k_m',
  '--host', '127.0.0.1', '--device', 'Vulkan1', '--gpu-layers', 'all',
  '--ctx-size', '4096', '--parallel', '1', '--predict', '512', '--temp', '0',
  '--seed', '42', '--no-cache-prompt', '--no-context-shift', '--no-webui'
)
llama-server @serverArgs --port 18083
```

From the repository root in a second PowerShell session, check that the local server is ready and run the evaluator.

```powershell
Invoke-RestMethod 'http://127.0.0.1:18083/health'
$env:NL2SQL_ENDPOINT = 'http://127.0.0.1:18083/v1/chat/completions'
$env:NL2SQL_MODEL = 'qwen2.5-coder-1.5b-instruct-q4_k_m'
Remove-Item Env:NL2SQL_API_KEY -ErrorAction SilentlyContinue
moon update
moon run --quiet --target native cmd/eval -- --live > nl2sql-prompt-only.json
if ($LASTEXITCODE -ne 0) { throw 'Live evaluation failed. Inspect nl2sql-prompt-only.json.' }
```

To reproduce the follow-up, stop the first server with Ctrl+C. In its PowerShell session, start the same model with the pinned JSON grammar. The grammar SHA-256 is `1a3e3469892957861029adcd24ad0c886b778a942dd4a18cc146238ad56474dd`. [llama.cpp JSON grammar](https://github.com/ggml-org/llama.cpp/blob/b12503/grammars/json.gbnf)

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/ggml-org/llama.cpp/b12503/grammars/json.gbnf' -OutFile json-b12503.gbnf
llama-server @serverArgs --port 18084 --grammar-file json-b12503.gbnf
```

From the repository root in the evaluation session, run the same evaluator.

```powershell
Invoke-RestMethod 'http://127.0.0.1:18084/health'
$env:NL2SQL_ENDPOINT = 'http://127.0.0.1:18084/v1/chat/completions'
moon run --quiet --target native cmd/eval -- --live > nl2sql-json-grammar.json
if ($LASTEXITCODE -ne 0) { throw 'Live evaluation failed. Inspect nl2sql-json-grammar.json.' }
```

## Follow-up with plan examples and compatible replies

The updated planner prompt gives complete plan and abstention examples from unrelated schemas. The reply decoder treats a JSON null limit as omitted and accepts finite JSON numbers quoted as real filter values. Table, column, join, and projection validation still runs before SQL execution.

The follow-up uses the same model, eight questions, SQLite snapshot, and server JSON grammar as the comparison above. On the structured path, the correct cases were the large order ID lookup, the missing-note count, and the empty result. The spend-by-user query executed with an unintended null filter and returned no rows. Plan validation rejected four other replies for unknown columns or invalid grouping. Neither path correctly abstained on either unanswerable question.

| Metric | Original structured plan | Updated structured plan | Direct SQL |
| --- | ---: | ---: | ---: |
| Result accuracy | 0/6 | 3/6 | 4/6 |
| Invalid output | 8/8 | 4/8 | 2/8 |
| Correct abstention | 0/2 | 0/2 | 0/2 |

The two follow-up runs produced byte-identical reports. Both paths recorded zero provider and execution failures. To reproduce, use evaluator revision `ff2c28544b0b5f34079a77a635efc98d3dbc16f8` and the JSON grammar server command under [Reproduce](#reproduce). [Raw follow-up results](results/qwen2.5-coder-1.5b-plan-followup.json)

## Follow-up with a shared schema answerability check

This development-set follow-up added the same model check to each path before query generation. It sends the question, the table and column names, and four example exchanges from unrelated schemas. The examples cover recorded measures, unavailable inputs to a calculation, and a missing event time. The check returns explicit approval or a refusal naming the missing data. A malformed assessment counts as invalid output. A refusal skips query generation and SQLite data execution. The generation prompts, catalog input, SQL policy, and scoring rules are the same as in the preceding follow-up.

The local run used the pinned Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights, Windows Vulkan build, JSON grammar, eight questions and SQLite snapshot from the previous comparison. A baseline run at `c334bd9d14ea95481ce4577f23218bf49b297f25` reproduced the previously published outcomes and raw replies. The updated evaluator reports two byte-identical local runs.

| Metric | Structured plan before | Structured plan with check | Direct SQL before | Direct SQL with check |
| --- | ---: | ---: | ---: | ---: |
| Result accuracy | 3/6 (50%) | 3/6 (50%) | 4/6 (66.7%) | 4/6 (66.7%) |
| Invalid output | 4/8 (50%) | 2/8 (25%) | 2/8 (25%) | 1/8 (12.5%) |
| Correct abstention | 0/2 (0%) | 2/2 (100%) | 0/2 (0%) | 2/2 (100%) |
| False abstention | 0/6 (0%) | 0/6 (0%) | 0/6 (0%) | 0/6 (0%) |

Both paths declined `unanswerable-profit` because net profit was unavailable and `unanswerable-delivery-date` because the database did not record delivery times. All six answerable cases produced the same generation replies as the baseline, including the valid query that returned zero rows. For `spend-by-user`, the structured plan returned zero rows after adding a null filter, and direct SQL returned only one user. Plan validation rejected `top-stock` and `stock-by-region`, while SQLite rejected the direct SQL for `top-stock` because it referenced an unknown column. Both paths recorded zero provider and execution failures. This fixed set was used to develop the check, so the figures describe its behavior on these eight questions. [Raw replies and per-question results](results/qwen2.5-coder-1.5b-answerability.json)

To reproduce the updated run, use evaluator revision `8b0be3df6a199bf54c7a5f6df9387060eb2d13b3` with the same server command, weights, and grammar as above. The check and query generation each have a 30-second model request timeout. Supported cases make two requests per path. [Server and evaluator commands](../README.md#reproduce-the-comparison)

## Independent museum holdout

The synthetic museum fixture covers galleries, artworks, exhibitions, and loans. The 20 English and Chinese questions include joins, aggregates, a date range, duplicate rows, an empty result, and requests for facts absent from the schema. The labels and reference replies were committed at `84d23089ce7b682ee8acde08c873337618977fbd` before any model run on these questions. Both fixture paths then passed all 20 reference outcomes. The prompts and answerability examples stayed at their development-set settings throughout the holdout. [Questions and reference replies](holdout/questions.json) · [SQLite schema and sample data](holdout/museum.sql)

Both paths ran on the same local Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights and Windows Vulkan runtime with the previously pinned JSON grammar, temperature 0, and seed 42. A correct abstention is an explicit refusal on an unanswerable question. A false abstention is an explicit refusal on an answerable one, including a question whose correct result is empty. The abstention counts grade the decision. Result accuracy uses typed rows over all 12 answerable questions, including any refusals or errors.

| Metric | Structured query plan | Direct SQL |
| --- | ---: | ---: |
| Correct abstention | 4/8 (50%) | 4/8 (50%) |
| False abstention | 0/12 (0%) | 0/12 (0%) |
| Result accuracy | 3/12 (25%) | 6/12 (50%) |
| Invalid output | 7/20 (35%) | 2/20 (10%) |

The shared check refused the same four questions on both paths and allowed all 12 answerable questions through. Its refusal for `missing-transport-date` described missing loan information generally. The actual gap is the departure date. Loan requests and returns are recorded.

| Unanswerable case approved by the check | Structured query plan | Direct SQL |
| --- | --- | --- |
| Contractual loan due date | Ran a query using a fixed date unrelated to the loan contract | Compared return dates with request dates |
| Artist birth country | Produced a plan that failed decoding | Queried a nonexistent country column |
| After-hours security assignments | Produced a plan that failed decoding | Queried a nonexistent security guard column |
| Restoration history | Referenced a nonexistent `fixes` column | Used completed loans as a proxy for restorations |

On the valid North Annex query, direct SQL returned the expected zero rows and the structured plan used an invalid join. Both paths omitted the painting filter in the duplicate-values question. Each run recorded zero provider and execution failures. The two complete reports were byte-identical. [Raw assessment and generation replies](results/qwen2.5-coder-1.5b-museum-holdout.json)

To reproduce these numbers, use evaluator revision `591625c409c744ba7af7bd7d150aa774ae4feb96` and the bundled `eval/holdout/museum.db` snapshot. Its SHA-256 is `562f9a84aa08da75fcabc1dc8b7261a6c988be1b014875a7361ce26211d39c5d`. Start the pinned local server and use `--live --holdout`. The corresponding fixture replay uses `--fixture --holdout`. [Server and evaluator commands](../README.md#reproduce-the-comparison)

## Catalog-verified museum reevaluation

The original check missed four absent facts in the museum catalog. The model used dates unrelated to loan deadlines, invented birth-country and security-assignment fields, and interpreted a returned loan as evidence of restoration. The revised first check asks about every fact needed by the question. After an initial approval, a second model call returns either `{"missing_column":null}` or an existing table name paired with a proposed missing column. The evaluator checks the claim against the SQLite catalog. If the named column exists anywhere in the schema, the query can proceed even if its filters match no rows.

We selected the second check on 24 development examples drawn from food cooperatives, observatories and sports leagues. It correctly refused 9/9 unanswerable questions. Of the 15 answerable questions it approved 11, falsely refused three and produced one invalid reply. Two false refusals came from the initial check and one from the second check. The museum set was used for reevaluation only after the implementation was fixed. [Development cases](schema-evidence-dev.json) · [Per-case decisions](results/qwen2.5-coder-1.5b-schema-evidence-development.json)

| Museum metric | Structured plan, original → revised | Direct SQL, original → revised |
| --- | ---: | ---: |
| Correct abstentions | 4/8 → 8/8 | 4/8 → 8/8 |
| False abstentions | 0/12 → 0/12 | 0/12 → 0/12 |
| Correct results on answerable questions | 3/12 → 3/12 | 6/12 → 6/12 |
| Invalid output | 7/20 → 4/20 | 2/20 → 0/20 |

The two live runs used the pinned local weights, runtime, JSON grammar and museum snapshot from the original evaluation. Both produced byte-identical reports and recorded zero provider or execution failures. For all 12 answerable questions the generation replies matched the original replies on each path. Direct SQL returned zero rows for North Annex and the structured plan still failed join validation. Abstention scores measure the decision itself. The refusal for the Spanish audio guide gave an unrelated reason. [Original replies](results/qwen2.5-coder-1.5b-museum-holdout.json) · [Revised replies](results/qwen2.5-coder-1.5b-museum-schema-evidence.json)

To reproduce the revised scores, use evaluator revision `9a40d0b0bbf7d6c87d07ca7efa8389f13e5881f9`, start the pinned local server, and run `moon run --quiet --target native cmd/eval -- --live --holdout` from the repository root. [Server setup and evaluator commands](../README.md#reproduce-the-comparison)

## JOIN generation on the museum holdout

Four structured replies in the catalog-verified baseline failed before SQLite executed a query. Two failed foreign-key validation and two failed plan decoding. [Baseline replies and validation errors](results/qwen2.5-coder-1.5b-museum-schema-evidence.json)

| Museum question ID | Why the first plan failed | What the question required |
| --- | --- | --- |
| `ground-floor-galleries` | The plan added exhibitions and tried to join artworks through exhibitions. Those tables share no direct foreign key. | Filter galleries by floor and select the gallery name. All columns are on one table. |
| `works-after-year` | The plan used column names for `via`, a tagged projection for a grouping key, and an array for ordering. It also filtered exhibition dates. | Filter artworks by acquisition year and sort their titles. |
| `coverage-by-medium` | The grouping key used the tagged select syntax. The plan also included a superfluous join to galleries. | Group artworks by medium and sum their insured values, using a plain column reference for the grouping key. |
| `north-annex-empty` | The plan tried to reach galleries through an undeclared artworks–exhibitions edge and filtered for a null gallery name. | Join artworks directly to galleries and compare the gallery name to North Annex. The expected result is empty. |

### Development and selection

We fixed nine new warehouse questions with their expected typed rows at `bdd9680`. The depot database includes an unassigned crate, a bay without crates, multiple scans and shifts, and a two-hop path through bays. We compared first-pass prompt changes and one-retry variants on this set. We selected a bounded retry that improved row accuracy, reduced invalid plans and preserved every previously valid first reply. The Native live CLI enables the retry. Library callers opt in with `retry_invalid=true`. The repair request contains the compiler error, table columns and declared foreign-key table pairs in both directions. The same compiler validates the replacement before execution. [Questions and reference queries](join-dev/questions.json) · [Depot schema and rows](join-dev/depot.sql)

On the depot set, structured row accuracy rose from 2/9 to 4/9 and invalid output fell from 3/9 to 1/9. The retry corrected the west-zone projection and the join for crates in bay A17. The two-hop Red crew query still chose an invalid edge. Three answerable questions were refused before generation. The empty-bay case matched the expected empty rows even though its first plan filtered scan readers instead of bay codes. The score measures rows on the snapshot. [Depot live replies](results/qwen2.5-coder-1.5b-depot-join-retry.json)

The implementation was frozen at `07b1a2ed34c8cd6c676ce880abc6e04c3b7b4def` before either live path was rerun on the museum database. The two paths used the same Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights, llama.cpp b12503 Vulkan server, JSON grammar, temperature 0 and seed 42. Both used the previously published assessment and first-generation prompts, question order, snapshot and row scorer. The structured path could make one extra model request per compile failure.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed results on answerable questions | 3/12 → 6/12 | 6/12 → 6/12 |
| Invalid output | 4/20 → 1/20 | 0/20 → 0/20 |
| Correct abstentions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions | 0/12 → 0/12 | 0/12 → 0/12 |

Exactly four structured plans triggered a second generation call. Galleries on floor 1, artworks acquired from 2022 onward and total insured value per medium all returned the expected rows using a single table. North Annex still failed validation. Its replacement correctly bound the gallery name but tried to join loans to galleries without a declared relationship. Direct SQL used the necessary artworks-to-galleries join and returned zero rows. Five other structured plans compiled and returned incorrect rows, so the retry never ran for them.

All 20 direct-SQL observations, answerability decisions and first structured replies matched the baseline, including the four rejected replies preserved under `rejected_plan_reply`. Two complete museum reruns produced byte-identical reports. Both paths recorded zero provider and execution failures. Abstention scores grade the decision, so the previously documented inaccurate reason for the Spanish audio guide still counts as a correct refusal. [Baseline report](results/qwen2.5-coder-1.5b-museum-schema-evidence.json) · [Reevaluated plans, SQL, bindings and rows](results/qwen2.5-coder-1.5b-museum-join-retry.json)

To reproduce, use revision `07b1a2e` and the pinned local server. The following commands run both paths for each set. To reproduce the pre-retry depot baseline, use revision `bdd9680` with the first command. [Server setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --live --join-dev
moon run --quiet --target native cmd/eval -- --live --holdout
```

## Direct and two-hop foreign-key routing

The previous North Annex replacement selected artwork titles and filtered on the right gallery name, but proposed reaching galleries through loans. The compiler rejected that edge. We tested whether the catalog could connect the two tables already named by the column expressions.

For a replacement plan rejected with `InvalidJoin`, the resolver considers ordinary column projections and filters referring to exactly two tables, including the starting table. It first looks for a unique direct foreign key, then for a unique two-edge path through one intermediate table. The compiler validates the resulting plan, including its column references and composite key conditions. Parallel keys, tied shortest paths, missing links and routes longer than two edges remain errors. The resolver changes only the joins. A valid first plan or valid replacement follows its original path.

### Radio development cases

We fixed eight questions on a separate radio scheduling database at `b014c5b`. Four require a direct foreign key and four require two hops. The cases cover both directions, nonempty and empty results, and repeated captions or callsigns. To isolate routing, a test takes each reference plan and inserts a detour into a direct join or removes the bridge from a two-hop join. All eight corrupted plans failed strict compilation. With resolution enabled, all eight produced the reference SQL and bindings and returned the expected typed rows. Separate tests cover ambiguous, disconnected and three-hop routes. [Development questions](route-dev/questions.json) · [Radio catalog and records](route-dev/radio.sql) · [Route regression test](../cmd/eval/score_wbtest.mbt)

In the full local-model run on the same radio questions, both paths scored 1/8 before and after. Five questions received malformed schema assessments before generation. Of the three that reached structured generation, one was correct and two assigned a column to the wrong table. The deterministic test above measures recovery when the endpoints and columns are specified correctly. [End-to-end radio replies](results/qwen2.5-coder-1.5b-radio-route.json)

### Frozen museum reevaluation

We froze the implementation at `845a3738564994910c570ea168a123226fc1afb3` before reevaluating the museum holdout. Both paths used the same local Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights, llama.cpp b12503 Vulkan server, pinned JSON grammar, temperature 0, seed 42 and museum snapshot as the preceding comparison. The prompts, model-call budget and scorer were unchanged.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed results on answerable questions | 6/12 → 7/12 | 6/12 → 6/12 |
| Invalid output | 1/20 → 0/20 | 0/20 → 0/20 |
| Correct abstentions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions | 0/12 → 0/12 | 0/12 → 0/12 |

North Annex accounted for the single improvement. All raw first and replacement model replies matched the baseline. The revised compiler replaced the invalid route with the declared artworks-to-galleries edge and executed the following SQL with `North Annex` as its text parameter. The other 19 structured observations and all 20 direct SQL observations matched the baseline. Five structured queries returned wrong rows. Two complete museum reruns produced byte-identical reports with zero provider or execution failures. [Previous report](results/qwen2.5-coder-1.5b-museum-join-retry.json) · [New raw replies, SQL, bindings and rows](results/qwen2.5-coder-1.5b-museum-route.json)

```sql
SELECT "artworks"."title" FROM "artworks"
JOIN "galleries" ON "galleries"."id" = +"artworks"."gallery_id"
WHERE "galleries"."name" = ?
```

To reproduce the live comparison, run the following from revision `845a373` with the pinned local server. Use `b014c5b` for the before measurements with the same commands. [Server and evaluator setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --live --route-dev
moon run --quiet --target native cmd/eval -- --live --holdout
```

The following Python check replays the recorded query without a model server. Run it from the repository root on the revision containing the report. The original database opens read-only. The query returns an empty list on the original data and a single title after moving one artwork in the memory copy.

```python
import json
import sqlite3
from pathlib import Path

report = json.loads(Path("eval/results/qwen2.5-coder-1.5b-museum-route.json").read_bytes())
case = next(row["structured"] for row in report["cases"] if row["id"] == "north-annex-empty")
assert case["params"] == [["Text", "North Annex"]]
params = (case["params"][0][1],)
source = sqlite3.connect("file:eval/holdout/museum.db?mode=ro", uri=True)
db = sqlite3.connect(":memory:")
source.backup(db)
source.close()
assert db.execute(case["sql"], params).fetchall() == []
db.execute("UPDATE artworks SET gallery_id=(SELECT id FROM galleries WHERE name=?) WHERE title=?",
           ("North Annex", "Night Market"))
assert db.execute(case["sql"], params).fetchall() == [("Night Market",)]
db.close()
```

## Missing text filters on executable plans

Five structured queries in the preceding museum run executed successfully and returned the wrong rows. All five omitted a requested text condition or used the wrong predicate for it. Three had no WHERE clause at all. [Baseline questions, SQL, parameters and rows](results/qwen2.5-coder-1.5b-museum-route.json)

| Museum question ID | Error visible in the executed baseline SQL |
| --- | --- |
| `exhibition-opening` | Selected every exhibition opening date and omitted the title Ink Routes. |
| `highest-print-cover` | Computed the maximum across all media. The maximum for prints is 7600, compared with 34000 for the full collection. |
| `painting-values-with-duplicates` | Returned all eight insured values. Restricting the input to paintings preserves the two separate rows valued at 34000. |
| `loaned-work-titles` | Used a null borrower in place of Hill Library and projected an extra artwork ID. |
| `recent-harbor-requests` | Applied the date condition without the Harbor Museum borrower and used a strict lower bound for an inclusive start date. |

### Tool development and operator controls

We fixed eleven new questions and a SQLite tool catalog at `40c3d65`. The rows distinguish a global maximum from a category maximum, preserve duplicate category prices, and include a null maker and a listing on the date boundary. Baseline structured accuracy was 6/11 and direct SQL accuracy was 9/11. Rewriting the first-generation prompt reached 8/11 but broke a previously correct per-category count. We selected a separate equality review that reached 8/11 and preserved all six previous successes. It recovered the maximum price for planes and both chisel price rows. Direct SQL stayed at 9/11. [Development questions](filter-dev/questions.json) · [Tool catalog](filter-dev/tools.sql) · [Raw development replies](results/qwen2.5-coder-1.5b-tools-text-filters.json)

The Native live CLI and structured evaluator can spend one extra call on a compilable, single-table first plan with empty filters, joins and grouping. The reviewer receives the question, the table name and its text-affinity column names. Its proposal must name an eligible column and a text value found in the question, allowing a regular English plural ending in *s*. The planner adds at most one bound equality. SQL, parameters and the original model and review replies are available in the live report. Library callers opt in through `review_filter` on `@planner.ask`.

A regression test passes the same unfiltered plan to the reviewer for eleven English and Chinese phrasings covering exclusion, alternatives and partial matches. Each case verifies the plan stays byte-identical and the model callback receives zero calls. A separate local-model probe for each category also recorded zero equality reviews. The original generator still made operator mistakes. The exclusion used `IS NULL`, the alternative used two equalities joined with `AND`, and the partial match failed plan decoding. These are limits of the end-to-end planner. The guard checks wording and does not establish equivalence for arbitrary paraphrases. [Control test](../planner/planner_test.mbt) · [Three live probes](results/qwen2.5-coder-1.5b-text-filter-controls.json)

From the repository root, run the eleven boundary controls with the following command. The single named test iterates over all eleven questions.

```powershell
moon test --target native planner -f 'text filter review preserves*'
```

### Frozen museum comparison

We committed the selected implementation at `09c4fe9ccea1e2e61eb8b1d5219b19413e431c9b` before rerunning the museum set. The two paths used identical local Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights, llama.cpp b12503 Vulkan server, JSON grammar, temperature 0, seed 42, museum snapshot, question order and scorer. The original generation, schema-check and invalid-plan retry prompts stayed fixed.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed results on answerable questions | 7/12 → 8/12 | 6/12 → 6/12 |
| Correct abstentions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions | 0/12 → 0/12 | 0/12 → 0/12 |
| Invalid output | 0/20 → 0/20 | 0/20 → 0/20 |

Exactly three questions triggered an extra model call. For the print maximum, the reviewer supplied `medium = 'print'`, and the executed query returned 7600. For Ink Routes it supplied `opens_on = 'Ink Routes'`, which returned no rows. The literal was present in the question and the column had text affinity, but the date column was the wrong semantic choice. The painting question received a null proposal and kept its unfiltered result. The two other baseline errors already had predicates and skipped review. Two complete museum runs produced byte-identical reports with zero provider or execution failures. No previously correct answer became wrong. All direct SQL observations and all original assessment and generation replies matched the baseline. [Previous report](results/qwen2.5-coder-1.5b-museum-route.json) · [New report with raw filter proposals and executed SQL](results/qwen2.5-coder-1.5b-museum-text-filters.json)

To reproduce, use revision `40c3d65` for the before measurements and `09c4fe9` for the frozen review. Start the pinned local server and run the following from the repository root. Each command generates fresh replies for both paths. [Server setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --live --filter-dev
moon run --quiet --target native cmd/eval -- --live --holdout
```

## Name and date column binding

The archived museum run showed how a valid query could return zero rows for the wrong reason. The model selected `exhibitions.opens_on` as its output, then proposed binding the exhibition name to that same date column. Both columns store SQLite text, so type checking alone accepted the proposal. [Baseline museum replies](results/qwen2.5-coder-1.5b-museum-text-filters.json)

### Calendar development

We fixed ten development questions and a calendar database at `8336d9f`. A release is literally named `2025-02-14` and was published on `2025-08-19`. Two other releases were published on `2025-02-14`. Asking when the release named `2025-02-14` was published reads `published_on` and filters `label`. Asking which releases were published on `2025-02-14` reads `label` and filters `published_on`. The meetup table adds a third plausible binding, the venue. Other cases cover a missing release, distinguishing an archive date from a publication date, and returning every recorded meetup date. [Questions and expected rows](binding-dev/questions.json) · [SQLite schema and rows](binding-dev/calendar.sql)

For a validated, unfiltered, ungrouped single-table plan that returns one ordinary text column, the reviewer receives that column's name and examples that distinguish the output from the filter. It still validates each proposed equality against the catalog and the literal in the question. The reviewer can return a null proposal for an unrestricted list. No database contents are sent in this review. [Planner implementation](../planner/filter.mbt)

| Calendar measure | Before | Frozen planner |
| --- | ---: | ---: |
| Exact equality proposal or explicit null, ten isolated reviewer calls | 8/10 | 10/10 |
| Correct typed rows, full structured path | 5/10 | 6/10 |
| Correct typed rows, full direct SQL path | 1/10 | 1/10 |
| False abstentions, each full path | 2/10 | 2/10 |

The isolated calls supplied the intended output column to the frozen reviewer. The probe artifact stores the system message, alternating user and assistant examples, and each final user input verbatim for replay at the same chat endpoint. Each compared the model's raw JSON with the expected filter independently of assessment and first-plan generation. The baseline chose `held_on` for the meetup name Cloud Circle and produced an incomplete equality for the all-dates question. The frozen reviewer chose `name` and explicit null respectively. In the full structured run only three first plans reached the review. Cloud Circle changed from zero rows to `2024-06-09`, Union Yard kept its venue filter, and the all-dates query kept every row. Early refusals and first plans with existing predicates account for the gap between the isolated and full-path scores. [Isolated requests and replies](results/qwen2.5-coder-1.5b-calendar-binding-probes.json) · [Full baseline](results/qwen2.5-coder-1.5b-calendar-binding-baseline.json) · [Full frozen run](results/qwen2.5-coder-1.5b-calendar-binding.json)

Six calendar controls and eleven earlier tool controls cover negation, alternatives and partial matches in English and Chinese. Each begins with an eligible unfiltered plan and fails if the equality reviewer is invoked or the plan changes. All 17 passed. These tests cover the optional review. Operator mistakes in the first generated plan remain possible. [Native regression tests](../planner/planner_test.mbt) · [Earlier end-to-end operator probes](#tool-development-and-operator-controls)

### Museum reevaluation

We froze the planner at `68b111d14a15f7d86f38e153e39b1b2b24fb6640` following calendar development, then ran both paths twice on the same 20 museum questions. Both runs used the pinned local Qwen2.5-Coder-1.5B-Instruct Q4_K_M, llama.cpp b12503 on Vulkan1, temperature 0, seed 42, the same SQLite snapshot, ordering and typed-row scorer. The museum questions have been reevaluated across several development rounds. This comparison measures change on that fixed benchmark.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed results on answerable questions | 8/12 → 9/12 | 6/12 → 6/12 |
| Correct abstentions on unanswerable questions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions on answerable questions | 0/12 → 0/12 | 0/12 → 0/12 |
| Invalid output | 0/20 → 0/20 | 0/20 → 0/20 |

Only `exhibition-opening` changed. The initial plan still selected the opening date with no filter. The new proposal was `{"equals":["title","Ink Routes"]}`. SQLite ran the query below with one bound text parameter, `Ink Routes`, and returned one typed text value, `2024-05-08`. Each of the other 19 structured observations and all 20 direct SQL observations matched the baseline. The remaining three structured errors were `loaned-work-titles`, `painting-values-with-duplicates` and `recent-harbor-requests`. Neither path had a provider or execution failure. Both complete reports had identical bytes. [Frozen museum replies, parameters and rows](results/qwen2.5-coder-1.5b-museum-column-binding.json) · [Previous museum run](results/qwen2.5-coder-1.5b-museum-text-filters.json)

```sql
SELECT "exhibitions"."opens_on" FROM "exhibitions" WHERE "exhibitions"."title" = ?
```

To reproduce the full comparison, use `8336d9f` for the baseline and `68b111d` for the frozen implementation. Start the pinned local server and set the endpoint and model as shown in the README, then run these commands from the repository root. Each live command generates fresh replies for both paths. [Server setup and environment](../README.md#reproduce-the-comparison)

```powershell
moon test --target native planner
moon run --quiet --target native cmd/eval -- --fixture --binding-dev
moon run --quiet --target native cmd/eval -- --live --binding-dev > calendar-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Category filtering with duplicate values

The previous museum report recorded an unfiltered projection for `painting-values-with-duplicates`. The reviewer returned `{"equals":null}`, so SQLite read all eight artwork values. Two of those rows were the expected paintings, each insured for 34000. The error was admitting six other artworks. [Baseline museum plan, review and rows](results/qwen2.5-coder-1.5b-museum-column-binding.json)

### Parcel development

We fixed eight questions and a six-row SQLite parcel database at `eb3b62f`. Three tubes weigh 420, 420 and 630 grams. A crate also weighs 420 grams. Filtering by shape must therefore preserve two copies of 420, exclude the third and return the 630 row. An unrestricted question expects all six rows. Other questions ask for a named parcel, a carrier, a different shape and a shape absent from the database. The existing scorer compares typed rows with multiplicity. [Questions and expected rows](category-dev/questions.json) · [Parcel data](category-dev/parcels.sql) · [Scorer](../cmd/eval/score.mbt)

A valid single-table first plan that projects one non-text column and omits filters and grouping now uses reviewer examples for individual rows. The examples distinguish asking for every item of a kind from asking for every item in the table. A proposed equality still requires an eligible text column and a value grounded in the question. This now covers `pouch` in `pouches` while keeping quoted literals exact. An accepted review changes only the filter. SQLite returns a row for each matching parcel. [Review code](../planner/filter.mbt) · [Duplicate-count and plural-boundary tests](../planner/planner_test.mbt)

| End-to-end development accuracy | Previous | Frozen |
| --- | ---: | ---: |
| Structured plan on parcels | 5/8 | 7/8 |
| Direct SQL on parcels | 3/8 | 3/8 |

The two recovered questions were `tube-repeat` and `pouch-masses`. The absent-shape question still returned every mass. Its wording “every matching parcel” triggered the existing pattern guard and skipped the equality review. During development, applying the row examples to aggregates also caused the tool catalog's global maximum to acquire a spurious filter. We kept the original aggregate review. The final tool run returned 90 for the global maximum and 48 for the plane maximum, with overall accuracy of 8/11 structured and 9/11 direct. [Parcel baseline](results/qwen2.5-coder-1.5b-parcels-category-baseline.json) · [Frozen parcel run](results/qwen2.5-coder-1.5b-parcels-category.json)

### Frozen museum comparison for category filters

At `e49ce2a70e2906520457d0c250ec62d5a7ebee80` we ran both paths twice on the same museum questions, SQLite snapshot and typed-row scorer. We used the local Qwen2.5-Coder-1.5B-Instruct Q4_K_M with llama.cpp b12503 on Vulkan1, temperature 0, seed 42 and the pinned JSON grammar. This museum set has been reevaluated across multiple rounds. The development changes in this round were fixed before the first museum run.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed rows on answerable questions | 9/12 → 10/12 | 6/12 → 6/12 |
| Correct abstentions on unanswerable questions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions on answerable questions | 0/12 → 0/12 | 0/12 → 0/12 |
| Invalid output across all questions | 0/20 → 0/20 | 0/20 → 0/20 |

Only the structured observation for `painting-values-with-duplicates` changed. The first plan still selected every insured value. The reviewer returned `{"equals":["medium","painting"]}`. SQLite executed the following query with the text parameter `painting` and returned two integer rows of 34000. Direct SQL still returned eight rows. The structured path still missed `loaned-work-titles` and `recent-harbor-requests`. All 20 direct SQL observations matched the previous run. Both paths had zero provider and execution failures. The two new reports were byte-identical. [Frozen replies, executed SQL and rows](results/qwen2.5-coder-1.5b-museum-category.json) · [Previous comparison](results/qwen2.5-coder-1.5b-museum-column-binding.json)

```sql
SELECT "artworks"."insured_value" FROM "artworks" WHERE "artworks"."medium" = ?
```

To reproduce the before and after runs, use `eb3b62f` for the baseline and `e49ce2a` for the frozen planner. Start the pinned local server and set the model and endpoint as in the README. From the repository root, use the fixture command to check the parcel database and expected row counts offline. Each live command evaluates both paths with fresh model replies. [Server setup and environment](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --category-dev
moon run --quiet --target native cmd/eval -- --live --category-dev > parcels-live.json
moon run --quiet --target native cmd/eval -- --live --filter-dev > tools-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Named borrowers and title-only results

In the previous museum run, `loaned-work-titles` selected both the loan's artwork ID and the artwork title. It filtered on `borrower IS NULL` even though the question named Hill Library, and returned no rows. Direct SQL already returned the two expected titles. [Previous museum replies and SQL](results/qwen2.5-coder-1.5b-museum-category.json)

### Score checkout development

We fixed eight questions and a sheet-music checkout database at `43d9fb5`. Cedar Choir appears as both renter and lender on different checkouts. A checkout with an unknown renter and a score that was never checked out distinguish a null predicate and a missing join from a named renter lookup. Two scores share the title Fir Waltz but have different IDs. The scorer compares the number of columns, typed values and duplicate rows. [Development questions and reference plans](borrower-dev/questions.json) · [Schema and data](borrower-dev/scores.sql)

The Native planner and the structured evaluator use role-specific examples for English clauses such as “requested by”, “borrowed by” and “supplied by”. The examples show which fields to return when the user asks for a display field, or for IDs as well. When the catalog contains a single recognized text column for that role, the prompt includes its exact name. The same guidance is available on an invalid-plan retry. SQLite still executes the validated model plan with bound parameters. The technique depends on recognized phrasing and catalog column names. [Prompt selection](../planner/named_party.mbt) · [Catalog and retry regression tests](../planner/planner_test.mbt)

| Correct typed results on the eight checkout questions | Previous | Frozen |
| --- | ---: | ---: |
| Structured plan | 2/8 | 7/8 |
| Direct SQL | 3/8 | 3/8 |

For Cedar Choir as renter, the structured query returned Fir Waltz twice and Rain Canon once, each as a single title column. For the same name as lender, it returned Open String and Dawn Chorus. The question asking for both IDs and titles returned two columns, and the ID-only question returned the single ID 14. An unknown renter matched the real null row. The absent named renter produced zero rows with a bound equality. The baseline had passed this last case by coincidence with `score_id IS NULL`. The one remaining structured failure queried every score for “every checkout” and included Silent Fugue, which had never been checked out. [Raw baseline](results/qwen2.5-coder-1.5b-scores-borrower-baseline.json) · [Raw frozen run](results/qwen2.5-coder-1.5b-scores-borrower.json)

### Frozen museum comparison for named borrowers

We froze the planner at `6c31da11d88e5ffde83bd5d4a31ed36726fc3a6e` before reevaluating both paths. We used the same SQLite snapshot, 20 questions, typed-row scorer, local Qwen2.5-Coder-1.5B-Instruct Q4_K_M weights, llama.cpp b12503 Vulkan1 runtime and JSON grammar as the previous round, with temperature 0 and seed 42. Two fresh runs produced byte-identical reports. This fixed museum benchmark has been reevaluated across multiple rounds.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct typed results on answerable questions | 10/12 → 11/12 | 6/12 → 6/12 |
| Correct abstentions on unanswerable questions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions on answerable questions | 0/12 → 0/12 | 0/12 → 0/12 |
| Invalid output across all questions | 0/20 → 0/20 | 0/20 → 0/20 |

For `loaned-work-titles`, SQLite executed the following query with one bound text parameter, `Hill Library`. The result had one column, `title`, and two rows, `Night Market` and `River Loom`. The other 19 structured observations and all 20 direct SQL observations matched the previous report. Neither path had a provider or execution failure. The only remaining structured error is `recent-harbor-requests`. [Frozen replies, executed SQL and rows](results/qwen2.5-coder-1.5b-museum-borrower.json) · [Previous museum results](results/qwen2.5-coder-1.5b-museum-category.json)

```sql
SELECT "artworks"."title" FROM "loans"
JOIN "artworks" ON "artworks"."id" = +"loans"."artwork_id"
WHERE "loans"."borrower" = ?
```

To reproduce the before and after comparison, use `43d9fb5` for the baseline and `6c31da1` for the frozen planner. Start the pinned server and set the model and endpoint as shown in the README. The fixture command checks the typed rows offline. Each live command generates fresh replies for both paths. [Server setup and environment](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --borrower-dev
moon run --quiet --target native cmd/eval -- --live --borrower-dev > scores-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Named parties and date boundaries

The archived museum plan for `recent-harbor-requests` selected request dates from all borrowers after June 1, 2024. It omitted the borrower equality and used a strict lower bound for an inclusive question. We developed the change on a separate booking database before rerunning the fixed museum benchmark. [Previous museum replies](results/qwen2.5-coder-1.5b-museum-borrower.json)

### Booking development

At `c3cf3c5` we fixed eight questions and a six-row SQLite database. Iris Studio has two bookings on March 10 and another on March 14. A different customer booked on March 10 as well, and Iris Studio also appears as a provider. Each query is scored on typed rows with multiplicity. [Questions and reference queries](range-dev/questions.json) · [Booking data](range-dev/bookings.sql)

For a supported terminal calendar comparison, the structured planner supplies the comparison operator and ISO date to the model. For recognized transaction wording and a short capitalized party name, it can also supply an equality when the catalog contains one matching text role. Customer and supplier cues use separate roles. The model still selects the date column and generates the plan. This guidance is used for initial generation and invalid-plan retries. [Calendar and role selection](../planner/date_range.mbt) · [Regression tests](../planner/planner_test.mbt)

| Correct rows on eight booking questions | Baseline | Frozen |
| --- | ---: | ---: |
| Structured plan | 1/8 | 6/8 |
| Direct SQL | 0/8 | 0/8 |

The inclusive customer query kept both March 10 bookings and March 14. The supplier query returned March 10 and March 12. The date-only query kept all five qualifying rows, and a named customer with no bookings on or after March 20 produced an empty result. The strict-after question still received a false abstention before plan generation. The party-only question still filtered by provider. The separate tool set scored 8/11 structured and 9/11 direct. [Baseline booking replies](results/qwen2.5-coder-1.5b-bookings-range-baseline.json) · [Frozen booking replies](results/qwen2.5-coder-1.5b-bookings-range.json)

### Frozen museum date range comparison

We froze the planner at `4aa98a0`, then ran both paths twice with the same 20 questions, SQLite snapshot, typed-row scorer, local Qwen2.5-Coder-1.5B-Instruct Q4_K_M, llama.cpp b12503 on Vulkan1, JSON grammar, temperature 0 and seed 42. The reports were byte-identical. The museum set has been evaluated over multiple rounds.

| Museum metric | Structured plan, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct rows on answerable questions | 11/12 → 12/12 | 6/12 → 6/12 |
| Correct abstentions on unanswerable questions | 8/8 → 8/8 | 8/8 → 8/8 |
| False abstentions on answerable questions | 0/12 → 0/12 | 0/12 → 0/12 |
| Invalid output across all questions | 0/20 → 0/20 | 0/20 → 0/20 |

Only the structured observation for `recent-harbor-requests` changed. SQLite now binds `2024-06-01` and `Harbor Museum` to the two predicates below. The only result is `2024-07-25`. The booking development data independently checks the inclusive operator with matching records on the start day. All 20 direct SQL observations matched the previous run. Both paths recorded zero provider and execution failures. [Previous museum report](results/qwen2.5-coder-1.5b-museum-borrower.json) · [Frozen museum report](results/qwen2.5-coder-1.5b-museum-range.json)

```sql
SELECT "loans"."requested_on" FROM "loans"
WHERE "loans"."requested_on" >= ? AND "loans"."borrower" = ?
```

Use `c3cf3c5` for the booking baseline and `4aa98a0` for the frozen planner. From the repository root, replay the fixture, then run the live comparisons with the pinned local endpoint and model. Each live command evaluates both paths. [Server setup and environment](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --range-dev
moon run --quiet --target native cmd/eval -- --live --range-dev > bookings-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Reviewing catalog contradictions in refusals

The booking question asking for dates for Iris Studio strictly after March 10, 2025 was refused by both paths before generation. The initial assessment claimed `bookings.provider` was absent even though the catalog lists it. The shared adapter now sends precise, quoted single-column claims contradicted by the named table to the existing schema review. The reviewer checks for a missing fact, and the final decision uses the live catalog. [Adapter](../planner/answerability.mbt) · [Regression test](../planner/planner_test.mbt) · [Baseline booking results](results/qwen2.5-coder-1.5b-bookings-range.json)

| Live development metric | Structured, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct rows on eight booking questions | 6/8 → 7/8 | 0/8 → 0/8 |
| False abstentions on eight booking questions | 1/8 → 0/8 | 1/8 → 0/8 |
| Correct abstentions on four missing screening facts | 4/4 → 4/4 | 4/4 → 4/4 |
| Correct rows on four answerable screening questions | 4/4 → 4/4 | 0/4 → 0/4 |

The structured booking query bound the customer and the exclusive date, returning March 14. Direct SQL ran but used the provider column and returned March 12. On the screening development set, the structured planner returned both valid empty results and correctly refused all four missing facts. The direct path passed the four refusals and produced invalid SQL for the four answerable questions. The screening reports matched byte for byte before and after the change. [Frozen booking results](results/qwen2.5-coder-1.5b-bookings-refusal-review.json) · [Screening questions](refusal-dev/questions.json) · [Raw screening results](results/qwen2.5-coder-1.5b-screenings-refusal-review.json)

We fixed the planner at `a12f327` before two fresh museum runs, using the same local model, SQLite snapshot and runtime settings as the preceding comparison. Both reports matched the archived museum report byte for byte. On the fixed 20-question benchmark, the structured and direct paths scored 12/12 and 6/12 on answerable questions, respectively. Both declined 8/8 unanswerable questions and falsely declined 0/12 answerable questions. [Museum report](results/qwen2.5-coder-1.5b-museum-range.json)

Run the following from the repository root after starting the pinned local server. Use `10fc5ca` for the baseline and `a12f327` for the frozen implementation. [Model and endpoint setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --refusal-dev
moon run --quiet --target native cmd/eval -- --live --refusal-dev > screenings-live.json
moon run --quiet --target native cmd/eval -- --live --range-dev > bookings-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Receiving parties without a date condition

In the booking baseline, the question asking for Iris Studio's booking dates produced an unfiltered plan. The equality review selected `provider` and returned dates for transactions Iris Studio supplied. The planner now shares the named-party recognition used for date comparisons with eligible party-only questions. It gives the model a bound equality suggestion for supported transaction wording with one catalogued receiving role and a short, capitalized name. It preserves the original spelling inside matched quotes. Cases that specify an item, ask about an unknown renter or leave the party ambiguous retain their existing prompts. [Planner](../planner/named_party.mbt) · [Regression test](../planner/planner_test.mbt)

The separate rental database contains Amber Guild as both renter and owner on different rows, a repeated rental date, a null renter and equipment categories. Its eight questions were fixed at `e66ee55`. No rental rows are included in the model prompt. [Questions and fixture plans](party-dev/questions.json) · [SQLite data](party-dev/rentals.sql)

| Live development metric | Structured, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct rows on booking questions | 7/8 → 8/8 | 0/8 → 0/8 |
| Correct rows on rental questions | 4/8 → 7/8 | 4/8 → 4/8 |

The booking query now binds `Iris Studio` to `customer` and returns March 9, March 10 twice and March 14. Three rental questions recovered, including the quoted party name. The explicit owner query still uses `owner`, and the unknown-renter question uses `IS NULL`. The absent named renter scored as correct because the query returned the expected empty result, although its filter used the wrong role. The equipment question still binds the plural `tripods` against singular stored values. The earlier score-checkout reports matched byte for byte. [Previous booking report](results/qwen2.5-coder-1.5b-bookings-refusal-review.json) · [New booking report](results/qwen2.5-coder-1.5b-bookings-party.json) · [Rental baseline](results/qwen2.5-coder-1.5b-rentals-party-baseline.json) · [New rental report](results/qwen2.5-coder-1.5b-rentals-party.json)

After freezing the implementation at `b9b3dce`, we ran both paths twice on the fixed museum set. The runs used the same local Qwen2.5-Coder-1.5B-Instruct Q4_K_M, pinned llama.cpp Vulkan runtime, SQLite snapshot and generation settings. Both outputs matched the archived report byte for byte. Structured accuracy was 12/12 and direct SQL accuracy was 6/12. Each path correctly declined 8/8 unanswerable questions and falsely declined 0/12 answerable questions. [Museum report](results/qwen2.5-coder-1.5b-museum-range.json)

Use `e66ee55` for the baseline and `b9b3dce` for the frozen planner. Run these commands from the repository root after starting the pinned local server. [Server setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --party-dev
moon run --quiet --target native cmd/eval -- --live --party-dev > rentals-live.json
moon run --quiet --target native cmd/eval -- --live --range-dev > bookings-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Plural category values

The rental model proposed `tripods` for the `item` column. SQLite stored the category as `tripod`, so the bound equality returned zero rows. The structured planner now checks an eligible unquoted category proposal against the local database. It preserves an exact stored match, and otherwise uses a regular singular candidate only if exactly one candidate exists in the same column. The probe uses a read-only query with bound parameters and the configured query timeout. Quoted values and name columns use their original equality. The extra query takes place only for an eligible filter-review proposal. No database values are sent to the model. [Implementation](../planner/category_value.mbt) · [Regression tests](../planner/planner_test.mbt)

The independent inspection database at `5d3afc1` contains singular categories, a literal plural that coexists with a singular, and two labels that differ by a final `s`. The regression test passes model proposals directly to the review step. It verifies regular and sibilant plurals, duplicate rows, exact stored plurals, quoted values, valid empty results and fallbacks when a local lookup is unavailable. [Inspection questions](plural-dev/questions.json) · [SQLite data](plural-dev/inspections.sql)

| Live development metric | Structured, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct rows on rental questions | 7/8 → 8/8 | 4/8 → 4/8 |
| Correct rows on inspection questions | 4/8 → 5/8 | 2/8 → 2/8 |

The corrected rental query returned three dates with `item = 'tripod'`. The inspection query for gaskets returned three rows, preserving the repeated date. Three inspection failures remain. A query for wrenches failed plan validation, another proposed the whole phrase `kind plates`, and the query for funnels was refused before planning. The rental set still has the previously documented empty-result case where the model uses the wrong role. [Previous rental results](results/qwen2.5-coder-1.5b-rentals-party.json) · [Frozen rental results](results/qwen2.5-coder-1.5b-rentals-plural.json) · [Inspection baseline](results/qwen2.5-coder-1.5b-inspections-plural-baseline.json) · [Frozen inspection results](results/qwen2.5-coder-1.5b-inspections-plural.json)

After freezing the planner at `6dedfcd`, we ran both paths twice on the fixed museum set with the same local Qwen2.5-Coder-1.5B-Instruct Q4_K_M, runtime, seed and SQLite snapshot. Both reports matched the archived result byte for byte. The answerable scores were 12/12 structured and 6/12 direct. Both paths correctly declined 8/8 unanswerable questions and falsely declined 0/12 answerable questions. The booking reports also matched the preceding comparison. [Museum results](results/qwen2.5-coder-1.5b-museum-range.json)

From the repository root, start the pinned local model and use `5d3afc1` for the inspection baseline or `6dedfcd` for the frozen planner. [Server setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --plural-dev
moon run --quiet --target native cmd/eval -- --live --plural-dev > inspections-live.json
moon run --quiet --target native cmd/eval -- --live --party-dev > rentals-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```

## Category column names in values

In the inspection baseline, the filter reviewer copied `kind plates` into an equality on `kind`. The planner now checks the entire unquoted value in the selected category column. If the complete value is absent and its leading word repeats the chosen column name, the planner checks the rest of the phrase as an exact value in that same column. For this case, SQLite binds `plates` and returns `2025-08-07`. The model still proposes `kind plates`. [Implementation](../planner/category_value.mbt) · [Previous inspection results](results/qwen2.5-coder-1.5b-inspections-plural.json) · [New inspection results](results/qwen2.5-coder-1.5b-inspections-category-descriptors.json)

The separate returns dataset contains both `cable` and `cables`, and both `category adapters` and `adapters`. Regression tests inject a reviewer proposal to verify that the repeated column prefix is removed only when the alternative exists. They also cover case variations in the prefix, multiword values, another column's name, quoted values, empty results and duplicate rows. The live returns model already proposed `cables` on the relevant question, so that case exercises the new behavior in the deterministic test. [Questions](descriptor-dev/questions.json) · [SQLite data](descriptor-dev/returns.sql) · [Regression test](../planner/planner_test.mbt)

| Live development metric | Structured, before → after | Direct SQL, before → after |
| --- | ---: | ---: |
| Correct rows on inspection questions | 5/8 → 6/8 | 2/8 → 2/8 |
| Correct rows on returns questions | 6/8 → 6/8 | 2/8 → 2/8 |

Only the `exact-plural` inspection case changed. The two remaining inspection failures were a malformed plan for wrenches and a false abstention for funnels. The returns reports matched byte for byte. Both paths falsely declined two answerable returns questions. The rental report also matched the previous run. [Returns results](results/qwen2.5-coder-1.5b-returns-category-descriptors.json)

After freezing the planner at `02ff67b`, we reran both paths twice on the fixed museum set with local Qwen2.5-Coder-1.5B-Instruct Q4_K_M and the existing runtime settings and snapshot. Both reports matched the archived report byte for byte. The structured and direct paths answered 12/12 and 6/12 answerable questions correctly, respectively. Both correctly declined 8/8 unanswerable questions and falsely declined 0/12 answerable questions. [Museum results](results/qwen2.5-coder-1.5b-museum-range.json)

Use `58c1a1d` for the baseline and `02ff67b` for the frozen planner. Start the pinned server and run the commands from the repository root. [Server setup](../README.md#reproduce-the-comparison)

```powershell
moon run --quiet --target native cmd/eval -- --fixture --descriptor-dev
moon run --quiet --target native cmd/eval -- --live --descriptor-dev > returns-live.json
moon run --quiet --target native cmd/eval -- --live --plural-dev > inspections-live.json
moon run --quiet --target native cmd/eval -- --live --holdout > museum-live.json
```
