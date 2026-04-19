/*
	odin-sqlite3 — Reusable SQLite3 Binding
	File: vendor/odin-sqlite3/db.odin

	Thin procedural helpers over the raw C API.
	No reflection, no generics — callers work with prepared statements directly.
*/
package sqlite3

import "core:c"
import "core:strings"

// db_open opens (or creates) a SQLite database at path.
// Returns nil + false on failure.
db_open :: proc(path: string) -> (db: ^Connection, ok: bool) {
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    rc := sqlite3_open(cpath, &db)
    if rc != .Ok {
        return nil, false
    }
    // WAL mode: better concurrent read/write performance.
    sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
    return db, true
}

// db_close closes the database connection.
db_close :: proc(db: ^Connection) {
    if db != nil { sqlite3_close_v2(db) }
}

// db_exec runs a SQL statement with no parameters and discards results.
// Returns true on success.
db_exec :: proc(db: ^Connection, sql: string) -> bool {
    csql := strings.clone_to_cstring(sql)
    defer delete(csql)
    rc := sqlite3_exec(db, csql, nil, nil, nil)
    return rc == .Ok
}

// db_exec_script runs multiple semicolon-separated SQL statements.
db_exec_script :: proc(db: ^Connection, script: string) -> bool {
    csql := strings.clone_to_cstring(script)
    defer delete(csql)
    errmsg: cstring
    rc := sqlite3_exec(db, csql, nil, nil, &errmsg)
    if rc != .Ok && errmsg != nil {
        sqlite3_free(rawptr(errmsg))
    }
    return rc == .Ok
}

// Stmt is a prepared statement ready for binding and stepping.
Stmt :: struct {
    handle: ^Statement,
    db:     ^Connection,
}

// db_prepare compiles a SQL statement.
// Must call stmt_finalize when done.
db_prepare :: proc(db: ^Connection, sql: string) -> (s: Stmt, ok: bool) {
    csql := strings.clone_to_cstring(sql)
    defer delete(csql)
    rc := sqlite3_prepare_v2(db, csql, c.int(len(sql)), &s.handle, nil)
    s.db = db
    return s, rc == .Ok
}

// stmt_finalize releases the prepared statement.
stmt_finalize :: proc(s: ^Stmt) {
    if s.handle != nil {
        sqlite3_finalize(s.handle)
        s.handle = nil
    }
}

// stmt_reset resets the statement for re-use with new bindings.
stmt_reset :: proc(s: ^Stmt) {
    sqlite3_reset(s.handle)
}

// Bind helpers — columns are 1-indexed (SQLite convention).
stmt_bind_text :: proc(s: ^Stmt, col: int, val: string) -> bool {
    cval := strings.clone_to_cstring(val)
    defer delete(cval)
    return sqlite3_bind_text(s.handle, c.int(col), cval, c.int(len(val)), TRANSIENT) == .Ok
}

stmt_bind_int :: proc(s: ^Stmt, col: int, val: int) -> bool {
    return sqlite3_bind_int64(s.handle, c.int(col), c.int64_t(val)) == .Ok
}

stmt_bind_i64 :: proc(s: ^Stmt, col: int, val: i64) -> bool {
    return sqlite3_bind_int64(s.handle, c.int(col), c.int64_t(val)) == .Ok
}

stmt_bind_null :: proc(s: ^Stmt, col: int) -> bool {
    return sqlite3_bind_null(s.handle, c.int(col)) == .Ok
}

// stmt_step advances to the next row. Returns true while rows remain.
stmt_step :: proc(s: ^Stmt) -> bool {
    return sqlite3_step(s.handle) == .Row
}

// stmt_exec runs a non-SELECT statement (INSERT / UPDATE / DELETE).
// Returns true on success (.Done).
stmt_exec :: proc(s: ^Stmt) -> bool {
    return sqlite3_step(s.handle) == .Done
}

// Column readers — 0-indexed (SQLite convention for column_*).
stmt_col_int  :: proc(s: ^Stmt, col: int) -> int  { return int(sqlite3_column_int64(s.handle, c.int(col))) }
stmt_col_i64  :: proc(s: ^Stmt, col: int) -> i64  { return i64(sqlite3_column_int64(s.handle, c.int(col))) }
// stmt_col_text returns an owned heap-allocated copy of the column value.
// Returns an owned empty string (not a literal) for SQL NULL, so callers
// can safely call delete() on every return value without crashing.
stmt_col_text :: proc(s: ^Stmt, col: int) -> string {
    cs := sqlite3_column_text(s.handle, c.int(col))
    if cs == nil { return strings.clone("") }
    return strings.clone_from(cs)
}
stmt_col_text_raw :: proc(s: ^Stmt, col: int) -> cstring {
    return sqlite3_column_text(s.handle, c.int(col))
}

// db_last_id returns the rowid of the most recent INSERT.
db_last_id :: proc(db: ^Connection) -> i64 {
    return i64(sqlite3_last_insert_rowid(db))
}

// db_errmsg returns the last error message for diagnostics.
db_errmsg :: proc(db: ^Connection) -> string {
    cs := sqlite3_errmsg(db)
    if cs == nil { return "" }
    return string(cs)
}
