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
