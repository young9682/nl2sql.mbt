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
