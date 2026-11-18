#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "moonbit.h"
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <winsqlite/winsqlite3.h>
#pragma comment(lib, "winsqlite3.lib")
#else
#include <sqlite3.h>
#include <time.h>
#endif

typedef struct {
  sqlite3 *db;
  sqlite3_stmt *stmt;
  uint64_t deadline_ms;
  int open_status;
} Query;

enum {
  EMPTY_STATEMENT = -1,
  MULTIPLE_STATEMENTS = -2,
  REJECTED_STATEMENT = -3
};

static uint64_t monotonic_ms(void) {
#ifdef _WIN32
  return GetTickCount64();
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
#endif
}

static int expired(void *data) {
  Query *query = data;
  return monotonic_ms() >= query->deadline_ms;
}

static int authorize(void *data, int action, const char *first,
                     const char *second, const char *database,
                     const char *trigger) {
  (void)data;
  (void)first;
  (void)trigger;
  switch (action) {
    case SQLITE_SELECT:
    case SQLITE_RECURSIVE:
      return SQLITE_OK;
    case SQLITE_READ:
      // SQLite may omit the database name for reads without column references,
      // such as count(*). The query cannot create temp tables or attach databases.
      if (database) return strcmp(database, "main") == 0 ? SQLITE_OK : SQLITE_DENY;
      return second && !*second ? SQLITE_OK : SQLITE_DENY;
    case SQLITE_FUNCTION:
      // Only SQLite built-ins exist on this private connection. Block the SQL
      // extension loader explicitly as well as leaving extension loading off.
      return second && sqlite3_stricmp(second, "load_extension") != 0
        ? SQLITE_OK : SQLITE_DENY;
    default:
      return SQLITE_DENY;
  }
}

static Query *from_handle(int64_t handle) {
  return (Query *)(intptr_t)handle;
}

static moonbit_bytes_t copy_bytes(const void *source, int length) {
  moonbit_bytes_t bytes = moonbit_make_bytes_raw(length);
  if (length > 0) {
    memcpy(bytes, source, (size_t)length);
  }
  return bytes;
}

MOONBIT_FFI_EXPORT int64_t nl2sql_sqlite_open(moonbit_bytes_t path,
                                              int32_t timeout_ms) {
  Query *query = calloc(1, sizeof(*query));
  if (!query) return 0;
  query->deadline_ms = monotonic_ms() + (uint64_t)timeout_ms;
  query->open_status = sqlite3_open_v2((const char *)path, &query->db,
                                    SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE, NULL);
  if (query->open_status == SQLITE_OK && sqlite3_db_readonly(query->db, "main") != 1) {
    query->open_status = SQLITE_READONLY;
  }
  if (query->open_status == SQLITE_OK) {
    query->open_status = sqlite3_db_config(query->db, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
  }
  if (query->open_status == SQLITE_OK) {
    query->open_status = sqlite3_db_config(query->db, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, NULL);
  }
  if (query->open_status == SQLITE_OK) {
    query->open_status = sqlite3_set_authorizer(query->db, authorize, NULL);
    sqlite3_limit(query->db, SQLITE_LIMIT_ATTACHED, 0);
    sqlite3_limit(query->db, SQLITE_LIMIT_SQL_LENGTH, 64 * 1024);
    sqlite3_limit(query->db, SQLITE_LIMIT_LENGTH, 1024 * 1024);
    sqlite3_progress_handler(query->db, 1000, expired, query);
  }
  return (int64_t)(intptr_t)query;
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_open_status(int64_t handle) {
  return from_handle(handle)->open_status;
}

MOONBIT_FFI_EXPORT void nl2sql_sqlite_close(int64_t handle) {
  Query *query = from_handle(handle);
  sqlite3_finalize(query->stmt);
  sqlite3_close(query->db);
  free(query);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t nl2sql_sqlite_error_message(int64_t handle, int32_t status) {
  Query *query = from_handle(handle);
  const char *message = query->db ? sqlite3_errmsg(query->db) : NULL;
  if (!message || strcmp(message, "not an error") == 0) {
    message = sqlite3_errstr(status);
  }
  return copy_bytes(message, (int)strlen(message));
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_prepare(int64_t handle, moonbit_bytes_t sql) {
  Query *query = from_handle(handle);
  if (expired(query)) return SQLITE_INTERRUPT;
  const char *tail = NULL;
  int rc = sqlite3_prepare_v3(query->db, (const char *)sql, -1,
                             SQLITE_PREPARE_NO_VTAB, &query->stmt, &tail);
  if (rc != SQLITE_OK) return rc;
  if (!query->stmt) return EMPTY_STATEMENT;
  if (*tail) {
    // Let SQLite distinguish trailing comments and empty semicolons from SQL.
    sqlite3_stmt *extra = NULL;
    rc = sqlite3_prepare_v3(query->db, tail, -1, SQLITE_PREPARE_NO_VTAB, &extra, NULL);
    if (extra) {
      sqlite3_finalize(extra);
      return MULTIPLE_STATEMENTS;
    }
    if (rc == SQLITE_ERROR || rc == SQLITE_AUTH) return MULTIPLE_STATEMENTS;
    if (rc != SQLITE_OK) return rc;
  }
  if (!sqlite3_stmt_readonly(query->stmt) || sqlite3_column_count(query->stmt) == 0) {
    return REJECTED_STATEMENT;
  }
  return SQLITE_OK;
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_parameter_count(int64_t handle) {
  return sqlite3_bind_parameter_count(from_handle(handle)->stmt);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_bind_null(int64_t handle, int32_t index) {
  return sqlite3_bind_null(from_handle(handle)->stmt, index);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_bind_integer(int64_t handle, int32_t index, int64_t value) {
  return sqlite3_bind_int64(from_handle(handle)->stmt, index, value);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_bind_real(int64_t handle, int32_t index, double value) {
  return sqlite3_bind_double(from_handle(handle)->stmt, index, value);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_bind_text(int64_t handle, int32_t index,
                                                moonbit_bytes_t value, int32_t length) {
  const char *text = length == 0 ? "" : (const char *)value;
  return sqlite3_bind_text(from_handle(handle)->stmt, index, text, length, SQLITE_TRANSIENT);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_bind_blob(int64_t handle, int32_t index,
                                                moonbit_bytes_t value, int32_t length) {
  sqlite3_stmt *stmt = from_handle(handle)->stmt;
  if (length == 0) return sqlite3_bind_zeroblob(stmt, index, 0);
  return sqlite3_bind_blob(stmt, index, value, length, SQLITE_TRANSIENT);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_step(int64_t handle) {
  Query *query = from_handle(handle);
  if (expired(query)) return SQLITE_INTERRUPT;
  int rc = sqlite3_step(query->stmt);
  if ((rc == SQLITE_ROW || rc == SQLITE_DONE) && expired(query)) return SQLITE_INTERRUPT;
  return rc;
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_column_count(int64_t handle) {
  return sqlite3_column_count(from_handle(handle)->stmt);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t nl2sql_sqlite_column_name(int64_t handle, int32_t index) {
  const char *name = sqlite3_column_name(from_handle(handle)->stmt, index);
  return copy_bytes(name, name ? (int)strlen(name) : 0);
}

MOONBIT_FFI_EXPORT int32_t nl2sql_sqlite_column_type(int64_t handle, int32_t index) {
  return sqlite3_column_type(from_handle(handle)->stmt, index);
}

MOONBIT_FFI_EXPORT int64_t nl2sql_sqlite_column_integer(int64_t handle, int32_t index) {
  return sqlite3_column_int64(from_handle(handle)->stmt, index);
}

MOONBIT_FFI_EXPORT double nl2sql_sqlite_column_real(int64_t handle, int32_t index) {
  return sqlite3_column_double(from_handle(handle)->stmt, index);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t nl2sql_sqlite_column_text(int64_t handle, int32_t index) {
  sqlite3_stmt *stmt = from_handle(handle)->stmt;
  const unsigned char *text = sqlite3_column_text(stmt, index);
  return copy_bytes(text, sqlite3_column_bytes(stmt, index));
}

MOONBIT_FFI_EXPORT moonbit_bytes_t nl2sql_sqlite_column_blob(int64_t handle, int32_t index) {
  sqlite3_stmt *stmt = from_handle(handle)->stmt;
  const void *blob = sqlite3_column_blob(stmt, index);
  return copy_bytes(blob, sqlite3_column_bytes(stmt, index));
}
