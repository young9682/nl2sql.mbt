const catalogSql = `
  WITH tables AS (
    SELECT name FROM pragma_table_list
    WHERE schema = 'main' AND type = 'table' AND name NOT GLOB 'sqlite_*'
  )
  SELECT 0 AS kind, t.name AS table_name, c.name, c.type, c.pk, c."notnull",
         0 AS key_id, c.cid AS seq, NULL
  FROM tables t JOIN pragma_table_xinfo(t.name, 'main') AS c WHERE c.hidden != 1
  UNION ALL
  SELECT 1, t.name, f."from", f."table", 0, 0, f.id, f.seq,
         coalesce(f."to", (SELECT p.name FROM pragma_table_xinfo(f."table", 'main') p
                           WHERE p.pk = f.seq + 1))
  FROM tables t JOIN pragma_foreign_key_list(t.name, 'main') AS f
  ORDER BY kind, table_name, key_id, seq`;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const sqlLimit = 64 * 1024;

export class QueryError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Open a private in-memory snapshot and transfer ownership of its bytes to SQLite.
export function openSnapshot({ capi, wasm, oo1 }, bytes) {
  const db = new oo1.DB();
  const connection = db.pointer;
  const check = (code) => {
    if (code === capi.SQLITE_OK) return;
    const message = capi.sqlite3_errmsg(connection);
    const detail = message === "not an error" ? capi.sqlite3_errstr(code) : message;
    switch (code & 0xff) {
      case capi.SQLITE_INTERRUPT:
        throw new QueryError("query_timeout", "SQLite query timed out.");
      case capi.SQLITE_AUTH:
      case capi.SQLITE_READONLY:
        throw new QueryError("query_rejected", detail);
      default:
        throw new QueryError("database_error", detail);
    }
  };
  const authorize = (_, action, _first, second, database) => {
    switch (action) {
      case capi.SQLITE_SELECT:
      case capi.SQLITE_RECURSIVE:
        return capi.SQLITE_OK;
      case capi.SQLITE_READ:
        // The WASM callback represents a null database name as pointer 0.
        if (database === "main" || (!database && second === "")) return capi.SQLITE_OK;
        break;
      case capi.SQLITE_FUNCTION:
        if (second && second.toLowerCase() !== "load_extension") return capi.SQLITE_OK;
        break;
    }
    return capi.SQLITE_DENY;
  };
  try {
    const length = bytes.byteLength;
    const image = capi.sqlite3_malloc(Math.max(length, 1));
    if (!image) throw new QueryError("database_error", "Could not allocate the SQLite snapshot.");
    wasm.heap8u().set(bytes, image);
    check(capi.sqlite3_deserialize(connection, "main", image, BigInt(length), BigInt(length),
      capi.SQLITE_DESERIALIZE_READONLY | capi.SQLITE_DESERIALIZE_FREEONCLOSE));
    check(capi.sqlite3_db_config(connection, capi.SQLITE_DBCONFIG_DEFENSIVE, 1, 0));
    check(capi.sqlite3_db_config(connection, capi.SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, 0));
    capi.sqlite3_limit(connection, capi.SQLITE_LIMIT_ATTACHED, 0);
    capi.sqlite3_limit(connection, capi.SQLITE_LIMIT_SQL_LENGTH, sqlLimit);
    capi.sqlite3_limit(connection, capi.SQLITE_LIMIT_LENGTH, 1024 * 1024);
  } catch (error) {
    db.close();
    throw error;
  }

  function bind(statement, index, [kind, value]) {
    switch (kind) {
      case "Null":
        // The pinned bundle's wrapper discards this return code.
        return wasm.exports.sqlite3_bind_null(statement, index);
      case "Integer":
        return capi.sqlite3_bind_int64(statement, index, BigInt(value));
      case "Real":
        return capi.sqlite3_bind_double(statement, index, value);
      case "Text":
      case "Blob": {
        const bytes = kind === "Text" ? encoder.encode(value) : Uint8Array.from(value);
        const pointer = wasm.scopedAlloc(Math.max(bytes.length, 1));
        wasm.heap8u().set(bytes, pointer);
        const bindBytes = kind === "Text" ? capi.sqlite3_bind_text : capi.sqlite3_bind_blob;
        return bindBytes(statement, index, pointer, bytes.length, capi.SQLITE_TRANSIENT);
      }
      default:
        throw new QueryError("database_error", "Unknown SQLite parameter type.");
    }
  }

  function readCell(statement, index) {
    switch (capi.sqlite3_column_type(statement, index)) {
      case capi.SQLITE_NULL:
        return ["Null"];
      case capi.SQLITE_INTEGER:
        return ["Integer", capi.sqlite3_column_int64(statement, index).toString()];
      case capi.SQLITE_FLOAT: {
        const value = capi.sqlite3_column_double(statement, index);
        return ["Real", Number.isFinite(value) ? value : String(value)];
      }
      case capi.SQLITE_TEXT: {
        const pointer = wasm.exports.sqlite3_column_text(statement, index);
        const length = capi.sqlite3_column_bytes(statement, index);
        try {
          return ["Text", decoder.decode(wasm.heap8u().subarray(pointer, pointer + length))];
        } catch {
          throw new QueryError("database_error", "SQLite returned invalid UTF-8.");
        }
      }
      case capi.SQLITE_BLOB:
        // SQLite uses a null pointer for a zero-length blob.
        return ["Blob", Array.from(capi.sqlite3_column_js(statement, index) ?? [])];
      default:
        throw new QueryError("database_error", "Unknown SQLite storage class.");
    }
  }

  function execute(sql, params, maxRows, timeoutMs, metadata = false) {
    if (![maxRows, timeoutMs].every((limit) => Number.isInteger(limit) && limit > 0 && limit <= 2147483647)) {
      throw new QueryError("database_error", "maxRows and timeoutMs must be positive 32-bit integers.");
    }
    if (sql.includes("\0") || encoder.encode(sql).byteLength > sqlLimit) {
      throw new QueryError("query_rejected", "SQL must be NUL-free and at most 64 KiB.");
    }
    const deadline = performance.now() + timeoutMs;
    const expired = () => Number(performance.now() >= deadline);
    const checkTime = () => { if (expired()) check(capi.SQLITE_INTERRUPT); };
    const scope = wasm.scopedAllocPush();
    let statement = 0;
    try {
      if (!metadata) check(capi.sqlite3_set_authorizer(connection, authorize, 0));
      capi.sqlite3_progress_handler(connection, 1000, expired, 0);
      const source = wasm.scopedAllocCString(sql);
      const [statementOut, tailOut, extraOut] = wasm.scopedAllocPtr(3);
      // Catalog SQL is fixed locally and needs SQLite's virtual PRAGMA tables.
      const flags = metadata ? 0 : capi.SQLITE_PREPARE_NO_VTAB;
      checkTime();
      const status = capi.sqlite3_prepare_v3(connection, source, -1, flags, statementOut, tailOut);
      statement = wasm.peekPtr(statementOut);
      check(status);
      if (!statement) throw new QueryError("query_rejected", "Expected one SQL statement.");
      const tail = wasm.peekPtr(tailOut);
      if (wasm.heap8u()[tail]) {
        const status = capi.sqlite3_prepare_v3(connection, tail, -1, flags, extraOut, 0);
        const extra = wasm.peekPtr(extraOut);
        if (extra) capi.sqlite3_finalize(extra);
        if (extra || status === capi.SQLITE_ERROR || status === capi.SQLITE_AUTH) {
          throw new QueryError("query_rejected", "Expected a single SQL statement.");
        }
        check(status);
      }
      const count = capi.sqlite3_column_count(statement);
      if (!capi.sqlite3_stmt_readonly(statement) || count === 0) {
        throw new QueryError("query_rejected", "Expected a read-only query returning rows.");
      }
      if (capi.sqlite3_bind_parameter_count(statement) !== params.length) {
        throw new QueryError("database_error", "SQL parameter count does not match the bindings.");
      }
      params.forEach((param, index) => check(bind(statement, index + 1, param)));
      const columns = Array.from({ length: count }, (_, i) => capi.sqlite3_column_name(statement, i));
      const rows = [];
      for (;;) {
        checkTime();
        const status = capi.sqlite3_step(statement);
        checkTime();
        if (status === capi.SQLITE_DONE) return { columns, rows, truncated: false };
        if (status !== capi.SQLITE_ROW) check(status);
        if (rows.length === maxRows) return { columns, rows, truncated: true };
        rows.push(columns.map((_, index) => readCell(statement, index)));
      }
    } finally {
      if (statement) capi.sqlite3_finalize(statement);
      capi.sqlite3_progress_handler(connection, 0, null, 0);
      if (!metadata) capi.sqlite3_set_authorizer(connection, null, 0);
      wasm.scopedAllocPop(scope);
    }
  }

  function readCatalog() {
    const metadata = execute(catalogSql, [], 16384, 5000, true);
    if (metadata.truncated) throw new QueryError("database_error", "SQLite catalog exceeds the row limit.");
    const tables = new Map();
    const foreignKeys = [];
    let lastKey;
    for (const row of metadata.rows) {
      const [kind, table, name, type, pk, notNull, keyId, , target] = row.map(([, value]) => value);
      if (kind === "0") {
        if (!tables.has(table)) tables.set(table, { name: table, columns: [] });
        tables.get(table).columns.push({
          name, type, nullable: notNull === "0", primary_key: pk !== "0",
        });
      } else {
        if (!lastKey || lastKey.source_table !== table || lastKey.id !== keyId) {
          lastKey = {
            id: keyId, source_table: table, source_columns: [], target_table: type, target_columns: [],
          };
          foreignKeys.push(lastKey);
        }
        lastKey.source_columns.push(name);
        lastKey.target_columns.push(target ?? null);
      }
    }
    return {
      schema: { tables: [...tables.values()] },
      foreign_keys: foreignKeys.map(({ id, ...key }) => key),
    };
  }

  return {
    readCatalog,
    query: (sql, params = [], { maxRows = 100, timeoutMs = 5000 } = {}) =>
      execute(sql, params, maxRows, timeoutMs),
    close: () => db.close(),
  };
}
