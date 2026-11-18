import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import initSqlite from "@sqlite.org/sqlite-wasm";
import { runDemo } from "./demo.mjs";
import { openSnapshot, QueryError } from "./sqlite.mjs";

const fixture = new URL("../../sqlite/fixtures/orders.db", import.meta.url);
const questions = new URL("../../eval/questions.json", import.meta.url);

test("the command replays the default question without model configuration", () => {
  const env = { ...process.env };
  for (const key of ["NL2SQL_API_KEY", "NL2SQL_ENDPOINT", "NL2SQL_MODEL", "OPENAI_API_KEY"]) delete env[key];
  const demo = fileURLToPath(new URL("demo.mjs", import.meta.url));
  const output = JSON.parse(execFileSync(process.execPath, [demo], { env, encoding: "utf8" }));
  assert.equal(output.status, "ok");
  assert.match(output.sql, /JOIN "orders"/);
  assert.deepEqual(output.result.rows, [
    [["Text", "林"], ["Real", 50]],
    [["Text", "Sam"], ["Real", 20]],
  ]);
  assert.equal(output.context.foreign_keys.length, 2);
});

test("WasmGC and JS planner builds match on all eight fixture cases", async () => {
  const cases = JSON.parse(await readFile(questions, "utf8"));
  for (const example of cases) {
    const wasm = await runDemo(example.id);
    const js = await runDemo(example.id, { target: "js" });
    assert.deepEqual(wasm, js, example.id);
    if (example.expected_rows) {
      const expected = example.expected_rows;
      assert.equal(wasm.status, expected.length ? "ok" : "empty", example.id);
      const comparable = (rows) => example.ordered ? rows : rows.map((row) => JSON.stringify(row)).sort();
      assert.deepEqual(comparable(wasm.result.rows), comparable(expected), example.id);
    } else {
      assert.equal(wasm.status, "no_answer", example.id);
      assert.equal(wasm.answer, example.fixture_plan.no_answer);
      assert.equal(wasm.result, undefined);
    }
  }
  const limited = await runDemo("spend-by-user", { maxRows: 1 });
  assert.equal(limited.status, "truncated");
  assert.equal(limited.result.truncated, true);
  assert.deepEqual(limited.result.rows, [[["Text", "林"], ["Real", 50]]]);
});

test("SQLite WASM returns typed cells and checks query limits", async () => {
  const original = await readFile(fixture);
  const db = openSnapshot(await initSqlite(), original);
  try {
    const typed = db.query("SELECT id, amount, note, receipt FROM orders WHERE id = ?", [
      ["Integer", "9007199254740993"],
    ]);
    assert.deepEqual(typed.rows, [[["Integer", "9007199254740993"], ["Real", 42.5], ["Null"], ["Blob", []]]]);
    const values = [["Null"], ["Integer", "-9223372036854775808"], ["Real", 2], ["Text", "林\0Sam"], ["Blob", [1, 0, 255]]];
    assert.deepEqual(db.query("SELECT ?, ?, ?, ?, ?; -- trailing comment", values).rows, [values]);
    assert.equal(db.query("SELECT id FROM users", [], { maxRows: 2 }).truncated, false);
    assert.equal(db.query("SELECT id FROM users", [], { maxRows: 1 }).truncated, true);

    const before = db.query("SELECT id, name FROM users ORDER BY id");
    const disallowed = [
      "SELECT 1; SELECT 2",
      "SELECT 1; DELETE FROM users",
      "WITH ids AS (SELECT id FROM users) DELETE FROM users WHERE id IN ids RETURNING id",
      "ATTACH ':memory:' AS other",
    ];
    for (const statement of disallowed) {
      assert.throws(() => db.query(statement), { status: "query_rejected" }, statement);
    }
    // The pinned SQLite WASM build omits the SQL extension loader entirely.
    assert.throws(() => db.query("SELECT load_extension('missing')"), QueryError);
    // Caller SQL cannot access the virtual PRAGMA tables used by the fixed catalog query.
    assert.throws(() => db.query("SELECT * FROM pragma_table_list"), QueryError);
    assert.throws(() => db.query(
      "WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x + 1 FROM n WHERE x < 1000000000) SELECT sum(x) FROM n",
      [],
      { timeoutMs: 50 },
    ), { status: "query_timeout" });
    assert.deepEqual(db.query("SELECT id, name FROM users ORDER BY id"), before);
  } finally {
    db.close();
  }
  assert.deepEqual(await readFile(fixture), original);
});
