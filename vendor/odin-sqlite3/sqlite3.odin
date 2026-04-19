/*
	odin-sqlite3 — Reusable SQLite3 Binding
	File: vendor/odin-sqlite3/sqlite3.odin

	Minimal raw C bindings to SQLite3. Linked via the static library at
	ffi/sqlite/libsqlite3.a passed through -extra-linker-flags in each
	build script. No foreign import block — consistent with the tree-sitter
	binding pattern in this project.

	Adapted from github.com/saenai255/odin-sqlite3 (MIT).
	Stripped to the ~20 functions actually used by odin-lint; the full
	Result_Code enum is preserved for correctness.
*/
package sqlite3

import "core:c"

// Opaque handle types — never dereference.
Connection :: distinct rawptr
Statement  :: distinct rawptr

// SQLITE_TRANSIENT: tell SQLite to copy the string immediately (cast of -1).
TRANSIENT :: rawptr(~uintptr(0))
// SQLITE_STATIC: caller guarantees the string outlives the statement.
STATIC    :: rawptr(uintptr(0))

Result :: enum c.int {
    Ok         = 0,
    Error      = 1,
    Internal   = 2,
    Perm       = 3,
    Abort      = 4,
    Busy       = 5,
    Locked     = 6,
    NoMem      = 7,
    ReadOnly   = 8,
    Interrupt  = 9,
    IoErr      = 10,
    Corrupt    = 11,
    NotFound   = 12,
    Full       = 13,
    CantOpen   = 14,
    Protocol   = 15,
    Schema     = 17,
    TooBig     = 18,
    Constraint = 19,
    Mismatch   = 20,
    Misuse     = 21,
    NoLfs      = 22,
    Auth       = 23,
    Range      = 25,
    NotA_Db    = 26,
    Row        = 100,
    Done       = 101,
}

// Raw SQLite3 C API.
// Symbols use their full sqlite3_ names; linked via -extra-linker-flags.
@(default_calling_convention = "c")
foreign {
    sqlite3_open              :: proc(filename: cstring, db: ^^Connection) -> Result ---
    sqlite3_close_v2          :: proc(db: ^Connection) -> Result ---
    sqlite3_exec              :: proc(db: ^Connection, sql: cstring, cb: rawptr, arg: rawptr, errmsg: ^cstring) -> Result ---
    sqlite3_prepare_v2        :: proc(db: ^Connection, sql: cstring, nbyte: c.int, stmt: ^^Statement, tail: ^cstring) -> Result ---
    sqlite3_step              :: proc(stmt: ^Statement) -> Result ---
    sqlite3_finalize          :: proc(stmt: ^Statement) -> Result ---
    sqlite3_reset             :: proc(stmt: ^Statement) -> Result ---
    sqlite3_bind_text         :: proc(stmt: ^Statement, col: c.int, val: cstring, n: c.int, dtor: rawptr) -> Result ---
    sqlite3_bind_int          :: proc(stmt: ^Statement, col: c.int, val: c.int) -> Result ---
    sqlite3_bind_int64        :: proc(stmt: ^Statement, col: c.int, val: c.int64_t) -> Result ---
    sqlite3_bind_null         :: proc(stmt: ^Statement, col: c.int) -> Result ---
    sqlite3_column_int        :: proc(stmt: ^Statement, col: c.int) -> c.int ---
    sqlite3_column_int64      :: proc(stmt: ^Statement, col: c.int) -> c.int64_t ---
    sqlite3_column_text       :: proc(stmt: ^Statement, col: c.int) -> cstring ---
    sqlite3_column_count      :: proc(stmt: ^Statement) -> c.int ---
    sqlite3_column_name       :: proc(stmt: ^Statement, col: c.int) -> cstring ---
    sqlite3_errmsg            :: proc(db: ^Connection) -> cstring ---
    sqlite3_last_insert_rowid :: proc(db: ^Connection) -> c.int64_t ---
    sqlite3_changes           :: proc(db: ^Connection) -> c.int ---
    sqlite3_free              :: proc(ptr: rawptr) ---
}
