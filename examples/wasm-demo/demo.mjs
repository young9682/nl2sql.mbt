import { readFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import initSqlite from "@sqlite.org/sqlite-wasm";
import { openSnapshot, QueryError } from "./sqlite.mjs";

const root = new URL("../../", import.meta.url);

async function loadPlanner(target) {
  if (target === "js") {
    const path = "_build/js/release/build/examples/wasm-demo/wasm-demo.js";
    return (await import(new URL(path, root))).compile_demo_reply;
  }
  const path = "_build/wasm-gc/release/build/examples/wasm-demo/wasm-demo.wasm";
  const bytes = await readFile(new URL(path, root));
  const { instance } = await WebAssembly.instantiate(bytes, {}, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  return instance.exports.compile_demo_reply;
}

export async function runDemo(id = "spend-by-user", { maxRows = 100, target = "wasm-gc" } = {}) {
  if (target !== "wasm-gc" && target !== "js") {
    throw new QueryError("invalid_arguments", "Target must be wasm-gc or js.");
  }
  if (!Number.isInteger(maxRows) || maxRows <= 0 || maxRows > 2147483647) {
    throw new QueryError("invalid_arguments", "--max-rows requires a positive 32-bit integer.");
  }
  const cases = JSON.parse(await readFile(new URL("eval/questions.json", root), "utf8"));
  const example = cases.find((item) => item.id === id);
  if (!example) throw new QueryError("invalid_arguments", `Unknown demo case: ${id}`);
  const [sqlite, bytes, compile] = await Promise.all([
    initSqlite(),
    readFile(new URL("sqlite/fixtures/orders.db", root)),
    loadPlanner(target),
  ]);
  const db = openSnapshot(sqlite, bytes);
  const { question } = example;
  try {
    const catalog = db.readCatalog();
    const reply = JSON.stringify(example.fixture_plan);
    const plan = JSON.parse(compile(JSON.stringify(catalog), reply));
    if (plan.status !== "query") return { question, ...plan };

    const { sql, params } = plan;
    const result = db.query(sql, params, { maxRows });
    const count = result.rows.length;
    let status = "ok";
    let answer = `The query returned ${count} row(s).`;
    if (result.truncated) {
      status = "truncated";
      answer = `Showing the first ${count} rows. More rows are available.`;
    } else if (count === 0) {
      status = "empty";
      answer = "No rows matched the query.";
    }
    return { status, question, answer, sql, params, result, context: { question, ...catalog } };
  } finally {
    db.close();
  }
}

if (import.meta.main) {
  try {
    const { positionals, values } = parseArgs({
      allowPositionals: true,
      options: {
        "max-rows": { type: "string", default: "100" },
        target: { type: "string", default: "wasm-gc" },
      },
    });
    if (positionals.length > 1 || !/^\d+$/.test(values["max-rows"])) {
      throw new QueryError("invalid_arguments", "Expected [CASE_ID] and an optional --max-rows N.");
    }
    const result = await runDemo(positionals[0], {
      maxRows: Number(values["max-rows"]),
      target: values.target,
    });
    console.log(JSON.stringify(result, null, 2));
    if (!["ok", "empty", "truncated", "no_answer"].includes(result.status)) process.exitCode = 1;
  } catch (error) {
    const status = error.status ?? (error.code?.startsWith("ERR_PARSE_ARGS") ? "invalid_arguments" : "demo_error");
    console.log(JSON.stringify({ status, detail: error.message }, null, 2));
    process.exitCode = status === "invalid_arguments" ? 2 : 1;
  }
}
