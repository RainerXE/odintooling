// call_graph.odin — SQLite-backed code-knowledge graph: open, CRUD and queries.
//
// The database is a CodeGraph database (see graph_schema.odin): nodes, edges, files,
// unresolved_refs, FTS5 and project_metadata come from CodeGraph's own schema, plus
// olt's odin_node_info table for memory roles and lint violations.
//
// API note: node handles in this file (the i64 ids) are the SQLite rowid of the
// nodes row. CodeGraph's node id is a TEXT key; edges and the odin_* tables use it.
// The handle <-> id translation stays inside this file so callers (C201, C202,
// C012-T3, C014/C015, the MCP tools) never see it.
//
// Paths: file_path columns hold project-relative paths with '/' separators, as
// CodeGraph does. The procs here accept and return absolute (or caller-relative)
// paths and translate at the boundary, using the project root derived from the
// database location (<root>/.codegraph/<db>).
package core

import "core:fmt"
import "core:hash"
import "core:os"
import "core:strings"
import "core:time"
import sq "../../vendor/odin-sqlite3"

// =============================================================================
// GraphDB
// =============================================================================

GraphDB :: struct {
    conn: ^sq.Connection,
    path: string,
    root: string,   // absolute project root; relative file_path values are rooted here
}

GraphNodeInfo :: struct {
    id:             i64,      // nodes.rowid
    name:           string,
    kind:           string,
    file:           string,   // absolute
    line:           int,
    memory_role:    string,
    lint_violations: string,
    signature:      string,
    return_type:    string,
}

GraphEdgeInfo :: struct {
    source_name: string,
    target_name: string,
    kind:        string,
    file:        string,
    line:        int,
}

// Column list shared by every query that yields a GraphNodeInfo (see scan_node_info).
@(private)
NODE_COLS :: `n.rowid, n.name, n.kind, n.file_path, n.start_line,
              COALESCE(i.memory_role,''), COALESCE(i.lint_violations,''),
              COALESCE(n.signature,''), COALESCE(n.return_type,'')`

@(private)
NODE_FROM :: `nodes n LEFT JOIN odin_node_info i ON i.node_id = n.id`

// Declaration kinds a call or reference can resolve to (file and import nodes
// are structure, not targets).
@(private)
TARGET_KINDS :: `('function','struct','enum','union','type_alias','constant','variable','enum_member','field')`

// =============================================================================
// Open / close
// =============================================================================

// graph_open opens (or creates) the graph database at path.
// A database written by an older olt (its own schema, before the CodeGraph
// schema) is a derived cache: it is discarded and rebuilt rather than migrated.
graph_open :: proc(path: string) -> (db: ^GraphDB, ok: bool) {
    if _is_legacy_graph_db(path) {
        _ = os.remove(path)
        _ = os.remove(fmt.tprintf("%s-wal", path))
        _ = os.remove(fmt.tprintf("%s-shm", path))
    }

    conn, conn_ok := sq.db_open(path)
    if !conn_ok { return nil, false }
    db = new(GraphDB)
    db.conn = conn
    db.path = strings.clone(path)
    db.root = _graph_root_for(path)

    sq.db_exec(db.conn, "PRAGMA journal_mode=WAL;")
    sq.db_exec(db.conn, "PRAGMA synchronous=NORMAL;")
    sq.db_exec(db.conn, "PRAGMA foreign_keys=ON;")

    if !_table_exists(db.conn, "nodes") {
        schema_ok, schema_err := sq.db_exec_script(db.conn, CODEGRAPH_SCHEMA_SQL)
        if !schema_ok {
            if schema_err != "" {
                fmt.eprintfln("export-symbols: graph schema failed: %s", schema_err)
                delete(schema_err)
            }
            graph_close(db)
            return nil, false
        }
        // schema.sql records version 1; record the version it really corresponds to.
        sq.db_exec(db.conn, fmt.tprintf(
            "INSERT OR IGNORE INTO schema_versions(version, applied_at, description) VALUES(%d, %d, '%s');",
            CODEGRAPH_SCHEMA_VERSION, _now_ms(), CODEGRAPH_SCHEMA_VERSION_NOTE))
    }

    odin_ok, odin_err := sq.db_exec_script(db.conn, ODIN_SCHEMA_SQL)
    if !odin_ok {
        if odin_err != "" {
            fmt.eprintfln("export-symbols: olt schema failed: %s", odin_err)
            delete(odin_err)
        }
        graph_close(db)
        return nil, false
    }
    return db, true
}

// graph_open_existing opens a graph database for reading. It never creates or
// rewrites anything: a missing file, or one written by an older olt (before the
// CodeGraph schema), is "not available" — the caller reports it or carries on
// without graph data. Only the exporter, via graph_open, creates a database.
graph_open_existing :: proc(path: string) -> (db: ^GraphDB, ok: bool) {
    if !os.is_file(path) { return nil, false }
    if _is_legacy_graph_db(path) { return nil, false }
    return graph_open(path)
}

// graph_close closes and frees the database.
graph_close :: proc(db: ^GraphDB) {
    if db == nil { return }
    sq.db_close(db.conn)
    delete(db.path)
    delete(db.root)
    free(db)
}

// graph_clear wipes all data (used before a full re-index).
graph_clear :: proc(db: ^GraphDB) {
    sq.db_exec(db.conn, "DELETE FROM unresolved_refs;")
    sq.db_exec(db.conn, "DELETE FROM edges;")
    sq.db_exec(db.conn, "DELETE FROM odin_node_info;")
    sq.db_exec(db.conn, "DELETE FROM nodes;")
    sq.db_exec(db.conn, "DELETE FROM files;")
}

@(private)
_now_ms :: proc() -> i64 {
    return i64(time.now()._nsec / 1_000_000)
}

@(private)
_table_exists :: proc(conn: ^sq.Connection, name: string) -> bool {
    s, ok := sq.db_prepare(conn, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;")
    if !ok { return false }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    return sq.stmt_step(&s)
}

// _is_legacy_graph_db reports whether path holds a database from before the
// CodeGraph schema: it has a nodes table, but no file_path column.
@(private)
_is_legacy_graph_db :: proc(path: string) -> bool {
    if !os.is_file(path) { return false }
    conn, ok := sq.db_open(path)
    if !ok { return false }
    defer sq.db_close(conn)
    if !_table_exists(conn, "nodes") { return false }
    s, s_ok := sq.db_prepare(conn, "SELECT COUNT(*) FROM pragma_table_info('nodes') WHERE name='file_path';")
    if !s_ok { return false }
    defer sq.stmt_finalize(&s)
    if sq.stmt_step(&s) { return sq.stmt_col_int(&s, 0) == 0 }
    return false
}

// _graph_root_for derives the project root from a database path:
// "<root>/.codegraph/x.db" -> "<root>"; any other location -> the db's directory.
// The result is absolute and heap-allocated.
@(private)
_graph_root_for :: proc(db_path: string) -> string {
    dir := filepath_dir(_abs_path(db_path))
    if strings.has_suffix(dir, "/.codegraph") {
        dir = filepath_dir(dir)
    }
    return strings.clone(dir)
}

// _abs_path makes p absolute against the current directory and resolves "." and
// ".." segments (lexically — symlinks are not followed). Lives in the temp allocator.
// Written out here, not taken from core:path/filepath, whose result type has
// changed between Odin releases.
@(private)
_abs_path :: proc(p: string) -> string {
    full := p
    if !strings.has_prefix(p, "/") {
        cwd, err := os.get_working_directory(context.temp_allocator)
        if err != nil { return p }
        full = fmt.tprintf("%s/%s", cwd, p)
    }
    parts := make([dynamic]string, context.temp_allocator)
    for seg in strings.split(full, "/", context.temp_allocator) {
        switch seg {
        case "", ".":
        case "..":
            if len(parts) > 0 { pop(&parts) }
        case:
            append(&parts, seg)
        }
    }
    return fmt.tprintf("/%s", strings.join(parts[:], "/", context.temp_allocator))
}

// graph_rel converts a caller path to the project-relative form stored in file_path.
// The result lives in the temp allocator.
graph_rel :: proc(db: ^GraphDB, p: string) -> string {
    abs_p := _abs_path(p)
    prefix := fmt.tprintf("%s/", db.root)
    if strings.has_prefix(abs_p, prefix) { return abs_p[len(prefix):] }
    return abs_p
}

// graph_abs converts a stored file_path back to an absolute path.
// The result is heap-allocated; the caller deletes it.
graph_abs :: proc(db: ^GraphDB, rel: string) -> string {
    if strings.has_prefix(rel, "/") { return strings.clone(rel) }
    return fmt.aprintf("%s/%s", db.root, rel)
}

// graph_dir_of returns the project-relative directory of a project-relative file
// ("" for a file at the root). In Odin a package is a directory, so this is the
// package key used to scope calls.
graph_dir_of :: proc(rel_file: string) -> string {
    i := strings.last_index_byte(rel_file, '/')
    if i < 0 { return "" }
    return rel_file[:i]
}

// =============================================================================
// Insert helpers
// =============================================================================

// _node_id builds CodeGraph's TEXT node id: stable across runs for the same declaration.
@(private)
_node_id :: proc(rel_file, kind, name: string, line, col: int) -> string {
    key := fmt.tprintf("%s\x00%s\x00%s\x00%d\x00%d", rel_file, kind, name, line, col)
    return fmt.tprintf("odin:%016x", hash.fnv64a(transmute([]u8)key))
}

@(private)
_file_node_id :: proc(rel_file: string) -> string {
    return fmt.tprintf("odin:file:%s", rel_file)
}

// graph_insert_node inserts a node and returns its handle (rowid), or -1 on failure.
// A file node for `file` must already exist (graph_insert_file); the node is
// attached to it with a `contains` edge, as CodeGraph does.
graph_insert_node :: proc(
    db:           ^GraphDB,
    name:         string,
    qualified:    string,
    kind:         string,
    file:         string,
    line:         int,
    signature:    string,
    is_exported:  bool,
    end_line:     int    = 0,
    start_col:    int    = 0,
    end_col:      int    = 0,
    docstring:    string = "",
    return_type:  string = "",
) -> i64 {
    rel := graph_rel(db, file)
    id  := _node_id(rel, kind, name, line, start_col)

    s, ok := sq.db_prepare(db.conn,
        `INSERT OR IGNORE INTO nodes(
            id, kind, name, qualified_name, file_path, language,
            start_line, end_line, start_column, end_column,
            docstring, signature, visibility, is_exported, return_type, updated_at)
         VALUES(?,?,?,?,?,'odin',?,?,?,?,NULLIF(?,''),NULLIF(?,''),?,?,NULLIF(?,''),?);`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)

    sq.stmt_bind_text(&s, 1,  id)
    sq.stmt_bind_text(&s, 2,  kind)
    sq.stmt_bind_text(&s, 3,  name)
    sq.stmt_bind_text(&s, 4,  qualified if qualified != "" else name)
    sq.stmt_bind_text(&s, 5,  rel)
    sq.stmt_bind_int(&s,  6,  line)
    sq.stmt_bind_int(&s,  7,  end_line if end_line >= line else line)
    sq.stmt_bind_int(&s,  8,  start_col)
    sq.stmt_bind_int(&s,  9,  end_col)
    sq.stmt_bind_text(&s, 10, docstring)
    sq.stmt_bind_text(&s, 11, signature)
    sq.stmt_bind_text(&s, 12, "public" if is_exported else "private")
    sq.stmt_bind_int(&s,  13, 1 if is_exported else 0)
    sq.stmt_bind_text(&s, 14, return_type)
    sq.stmt_bind_i64(&s,  15, _now_ms())
    if !sq.stmt_exec(&s) { return -1 }

    handle := _handle_of(db, id)
    if handle < 0 { return -1 }

    // file --contains--> node  (a file does not contain itself)
    if kind != "file" {
        ce, ce_ok := sq.db_prepare(db.conn,
            `INSERT OR IGNORE INTO edges(source, target, kind, line, col)
             VALUES(?, ?, 'contains', ?, ?);`)
        if ce_ok {
            sq.stmt_bind_text(&ce, 1, _file_node_id(rel))
            sq.stmt_bind_text(&ce, 2, id)
            sq.stmt_bind_int(&ce,  3, line)
            sq.stmt_bind_int(&ce,  4, start_col)
            sq.stmt_exec(&ce)
            sq.stmt_finalize(&ce)
        }
    }
    return handle
}

@(private)
_handle_of :: proc(db: ^GraphDB, id: string) -> i64 {
    s, ok := sq.db_prepare(db.conn, "SELECT rowid FROM nodes WHERE id=?;")
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, id)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// graph_set_package records the package a file declares.
graph_set_package :: proc(db: ^GraphDB, file: string, name: string) {
    rel := graph_rel(db, file)
    s, ok := sq.db_prepare(db.conn,
        "INSERT OR REPLACE INTO odin_package(file_path, dir, name) VALUES(?,?,?);")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, rel)
    sq.stmt_bind_text(&s, 2, graph_dir_of(rel))
    sq.stmt_bind_text(&s, 3, name)
    sq.stmt_exec(&s)
}

// _import_dir resolves an import path written in rel_file to a project-relative
// directory. Only plain relative paths ("../shared", "sub") name project code; a
// collection path ("core:fmt", "vendor:raylib") names something outside it.
@(private)
_import_dir :: proc(rel_file, path: string) -> (dir: string, ok: bool) {
    if strings.contains(path, ":") { return "", false }
    base := graph_dir_of(rel_file)
    full := path if base == "" else fmt.tprintf("%s/%s", base, path)
    parts := make([dynamic]string, context.temp_allocator)
    for seg in strings.split(full, "/", context.temp_allocator) {
        switch seg {
        case "", ".":
        case "..":
            if len(parts) == 0 { return "", false }   // leaves the project
            pop(&parts)
        case:
            append(&parts, seg)
        }
    }
    return strings.join(parts[:], "/", context.temp_allocator), true
}

// graph_add_import records one import declaration of a file.
graph_add_import :: proc(db: ^GraphDB, file: string, path: string, alias: string, line: int) {
    rel := graph_rel(db, file)
    dir, has_dir := _import_dir(rel, path)
    s, ok := sq.db_prepare(db.conn,
        `INSERT OR REPLACE INTO odin_import(file_path, line, path, alias, dir)
         VALUES(?1, ?2, ?3, NULLIF(?4,''), CASE WHEN ?5 THEN ?6 END);`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, rel)
    sq.stmt_bind_int(&s,  2, line)
    sq.stmt_bind_text(&s, 3, path)
    sq.stmt_bind_text(&s, 4, alias)
    sq.stmt_bind_int(&s,  5, 1 if has_dir else 0)
    sq.stmt_bind_text(&s, 6, dir)
    sq.stmt_exec(&s)
}

// graph_resolve_qualifier says what the "pkg" of a `pkg.name(...)` call in `file` refers to.
//   found=false              no import in this file goes by that name (so it is a value, not a package)
//   found, internal=false    an import outside the project (core:, vendor:, ...)
//   found, internal=true     a package in the project; dir is its directory (project-relative)
// An import goes by its explicit alias, else by the package name declared in the
// directory it names, else (nothing indexed there) by the last segment of its path.
//
// A collection other than core/base/vendor ("src:server") is set by a compiler flag
// the source does not show. It is taken to be project code when exactly one project
// directory declares a package of that name, and left external otherwise.
graph_resolve_qualifier :: proc(db: ^GraphDB, file: string, qualifier: string) -> (dir: string, internal: bool, found: bool) {
    s, ok := sq.db_prepare(db.conn,
        `SELECT i.dir, i.dir IS NOT NULL, i.path FROM odin_import i
         WHERE i.file_path = ?1 AND (
               i.alias = ?2
            OR (i.alias IS NULL AND (
                   EXISTS (SELECT 1 FROM odin_package p WHERE p.dir = i.dir AND p.name = ?2)
                OR i.path = ?2 OR i.path LIKE '%/' || ?2 OR i.path LIKE '%:' || ?2)))
         ORDER BY i.alias IS NULL LIMIT 1;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, graph_rel(db, file))
    sq.stmt_bind_text(&s, 2, qualifier)
    if !sq.stmt_step(&s) { return }

    found    = true
    internal = sq.stmt_col_int(&s, 1) != 0
    if internal {
        dir = sq.stmt_col_text(&s, 0)   // heap string; caller deletes
        return
    }

    path := sq.stmt_col_text(&s, 2)
    defer delete(path)
    colon := strings.index_byte(path, ':')
    if colon < 0 { return }
    collection := path[:colon]
    if collection == "core" || collection == "base" || collection == "vendor" { return }

    u, u_ok := sq.db_prepare(db.conn,
        "SELECT dir FROM odin_package WHERE name=? GROUP BY dir LIMIT 2;")
    if !u_ok { return }
    defer sq.stmt_finalize(&u)
    sq.stmt_bind_text(&u, 1, qualifier)
    first_dir := ""
    count := 0
    for sq.stmt_step(&u) {
        count += 1
        if count == 1 { first_dir = sq.stmt_col_text(&u, 0) } else { delete(first_dir); first_dir = ""; }
    }
    if count == 1 {
        internal = true
        dir = first_dir
    }
    return
}

// graph_file_node returns the handle of a file's `file` node (-1 if the file is unknown).
graph_file_node :: proc(db: ^GraphDB, file: string) -> i64 {
    return _handle_of(db, _file_node_id(graph_rel(db, file)))
}

// graph_insert_edge inserts a directed edge between two nodes (by handle).
graph_insert_edge :: proc(db: ^GraphDB, source_id, target_id: i64, kind: string, line: int, col: int = 0) {
    s, ok := sq.db_prepare(db.conn,
        `INSERT OR IGNORE INTO edges(source, target, kind, line, col)
         SELECT s.id, t.id, ?, ?, ? FROM nodes s, nodes t WHERE s.rowid=? AND t.rowid=?;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, kind)
    sq.stmt_bind_int(&s,  2, line)
    sq.stmt_bind_int(&s,  3, col)
    sq.stmt_bind_i64(&s,  4, source_id)
    sq.stmt_bind_i64(&s,  5, target_id)
    sq.stmt_exec(&s)
}

// graph_insert_file records a file with its content hash and creates its `file` node.
graph_insert_file :: proc(db: ^GraphDB, path: string, hash: string, ts: i64, size: int = 0, line_count: int = 1) {
    rel := graph_rel(db, path)
    ts_ms := ts * 1000

    s, ok := sq.db_prepare(db.conn,
        `INSERT OR REPLACE INTO files(path, content_hash, language, size, modified_at, indexed_at)
         VALUES(?,?,'odin',?,?,?);`)
    if !ok { return }
    sq.stmt_bind_text(&s, 1, rel)
    sq.stmt_bind_text(&s, 2, hash)
    sq.stmt_bind_int(&s,  3, size)
    sq.stmt_bind_i64(&s,  4, ts_ms)
    sq.stmt_bind_i64(&s,  5, ts_ms)
    sq.stmt_exec(&s)
    sq.stmt_finalize(&s)

    base := rel
    if i := strings.last_index_byte(rel, '/'); i >= 0 { base = rel[i+1:] }
    fn, fn_ok := sq.db_prepare(db.conn,
        `INSERT OR REPLACE INTO nodes(
            id, kind, name, qualified_name, file_path, language,
            start_line, end_line, start_column, end_column, is_exported, updated_at)
         VALUES(?, 'file', ?, ?, ?, 'odin', 1, ?, 0, 0, 0, ?);`)
    if !fn_ok { return }
    defer sq.stmt_finalize(&fn)
    sq.stmt_bind_text(&fn, 1, _file_node_id(rel))
    sq.stmt_bind_text(&fn, 2, base)
    sq.stmt_bind_text(&fn, 3, rel)
    sq.stmt_bind_text(&fn, 4, rel)
    sq.stmt_bind_int(&fn,  5, line_count if line_count > 0 else 1)
    sq.stmt_bind_i64(&fn,  6, ts_ms)
    sq.stmt_exec(&fn)
}

// graph_insert_unresolved stores a reference whose target could not be resolved.
// source_id is the referencing node's handle; a negative handle is ignored.
graph_insert_unresolved :: proc(db: ^GraphDB, source_id: i64, target_name, kind, file: string, line: int, col: int = 0) {
    if source_id < 0 { return }
    s, ok := sq.db_prepare(db.conn,
        `INSERT INTO unresolved_refs(from_node_id, reference_name, reference_kind, line, col,
                                     file_path, language, status, name_tail)
         SELECT id, ?, ?, ?, ?, ?, 'odin', 'failed', ? FROM nodes WHERE rowid=?;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    // olt has already tried to resolve this reference and found no target, which
    // is CodeGraph's 'failed' status. Leaving it 'pending' would make CodeGraph
    // report an interrupted run. name_tail is the last segment (pkg::fn -> fn).
    tail := target_name
    if i := strings.last_index(tail, "::"); i >= 0 { tail = tail[i+2:] }
    if i := strings.last_index_byte(tail, '.'); i >= 0 { tail = tail[i+1:] }
    sq.stmt_bind_text(&s, 1, target_name)
    sq.stmt_bind_text(&s, 2, kind)
    sq.stmt_bind_int(&s,  3, line)
    sq.stmt_bind_int(&s,  4, col)
    sq.stmt_bind_text(&s, 5, graph_rel(db, file))
    sq.stmt_bind_text(&s, 6, tail)
    sq.stmt_bind_i64(&s,  7, source_id)
    sq.stmt_exec(&s)
}

// graph_update_memory_role tags a node with its inferred memory role.
graph_update_memory_role :: proc(db: ^GraphDB, node_id: i64, role: string) {
    s, ok := sq.db_prepare(db.conn,
        `INSERT INTO odin_node_info(node_id, memory_role)
         SELECT id, ? FROM nodes WHERE rowid=?
         ON CONFLICT(node_id) DO UPDATE SET memory_role=excluded.memory_role;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, role)
    sq.stmt_bind_i64(&s,  2, node_id)
    sq.stmt_exec(&s)
}

// graph_update_return_type stores the extracted return type string for a node.
graph_update_return_type :: proc(db: ^GraphDB, node_id: i64, return_type: string) {
    s, ok := sq.db_prepare(db.conn, "UPDATE nodes SET return_type=NULLIF(?,'') WHERE rowid=?;")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, return_type)
    sq.stmt_bind_i64(&s,  2, node_id)
    sq.stmt_exec(&s)
}

// graph_update_violations attaches a JSON array of lint rule IDs to a node.
graph_update_violations :: proc(db: ^GraphDB, node_id: i64, violations_json: string) {
    s, ok := sq.db_prepare(db.conn,
        `INSERT INTO odin_node_info(node_id, lint_violations)
         SELECT id, ? FROM nodes WHERE rowid=?
         ON CONFLICT(node_id) DO UPDATE SET lint_violations=excluded.lint_violations;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, violations_json)
    sq.stmt_bind_i64(&s,  2, node_id)
    sq.stmt_exec(&s)
}

// graph_finalize runs once after an export: per-file node counts and the project
// metadata CodeGraph shows in `status`.
graph_finalize :: proc(db: ^GraphDB, indexer_version: string) {
    sq.db_exec(db.conn,
        `UPDATE files SET node_count=(SELECT COUNT(*) FROM nodes WHERE nodes.file_path=files.path);`)
    now := _now_ms()
    for kv in ([][2]string{{"indexer", "olt"}, {"indexer_version", indexer_version}, {"language", "odin"}}) {
        s, ok := sq.db_prepare(db.conn,
            `INSERT OR REPLACE INTO project_metadata(key, value, updated_at) VALUES(?,?,?);`)
        if !ok { continue }
        sq.stmt_bind_text(&s, 1, kv[0])
        sq.stmt_bind_text(&s, 2, kv[1])
        sq.stmt_bind_i64(&s,  3, now)
        sq.stmt_exec(&s)
        sq.stmt_finalize(&s)
    }
}

// =============================================================================
// Lookup helpers
// =============================================================================

// graph_find_node returns the handle of the first declaration matching name (exact).
// Returns -1 if not found.
graph_find_node :: proc(db: ^GraphDB, name: string) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        `SELECT rowid FROM nodes WHERE name=? AND kind IN `+TARGET_KINDS+` LIMIT 1;`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// graph_find_node_in_file returns the handle of a declaration matching name within a specific file.
graph_find_node_in_file :: proc(db: ^GraphDB, name: string, file: string) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        `SELECT rowid FROM nodes WHERE name=? AND file_path=? AND kind IN `+TARGET_KINDS+` LIMIT 1;`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    sq.stmt_bind_text(&s, 2, graph_rel(db, file))
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// graph_find_node_in_package returns the handle of a declaration matching name in
// the Odin package whose directory is dir (project-relative, "" for the root).
// A package is a directory and does not include its subdirectories.
graph_find_node_in_package :: proc(db: ^GraphDB, name: string, dir: string) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        `SELECT rowid FROM nodes
         WHERE name=?1 AND kind IN `+TARGET_KINDS+`
           AND CASE WHEN ?2 = '' THEN instr(file_path, '/') = 0
                    ELSE substr(file_path, 1, length(?2)+1) = ?2 || '/'
                         AND instr(substr(file_path, length(?2)+2), '/') = 0 END
         LIMIT 1;`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    sq.stmt_bind_text(&s, 2, dir)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// =============================================================================
// Query helpers (MCP tool backing)
// =============================================================================

@(private)
scan_node_info :: proc(db: ^GraphDB, s: ^sq.Stmt) -> GraphNodeInfo {
    rel := sq.stmt_col_text(s, 3)
    defer delete(rel)
    return GraphNodeInfo{
        id              = sq.stmt_col_i64(s, 0),
        name            = sq.stmt_col_text(s, 1),
        kind            = sq.stmt_col_text(s, 2),
        file            = graph_abs(db, rel),
        line            = sq.stmt_col_int(s, 4),
        memory_role     = sq.stmt_col_text(s, 5),
        lint_violations = sq.stmt_col_text(s, 6),
        signature       = sq.stmt_col_text(s, 7),
        return_type     = sq.stmt_col_text(s, 8),
    }
}

// graph_get_node returns a single declaration by name.
graph_get_node :: proc(db: ^GraphDB, name: string) -> (GraphNodeInfo, bool) {
    s, ok := sq.db_prepare(db.conn,
        `SELECT ` + NODE_COLS + ` FROM ` + NODE_FROM + `
         WHERE n.name=? AND n.kind IN ` + TARGET_KINDS + ` LIMIT 1;`)
    if !ok { return {}, false }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    if sq.stmt_step(&s) { return scan_node_info(db, &s), true }
    return {}, false
}

// graph_free_node_info frees all heap-allocated strings inside a GraphNodeInfo.
graph_free_node_info :: proc(n: GraphNodeInfo) {
    delete(n.name); delete(n.kind); delete(n.file)
    delete(n.memory_role); delete(n.lint_violations); delete(n.signature); delete(n.return_type)
}

// graph_get_callers returns all nodes that have a 'calls' edge to node_id.
graph_get_callers :: proc(db: ^GraphDB, node_id: i64) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT DISTINCT ` + NODE_COLS + ` FROM ` + NODE_FROM + `
         JOIN edges e ON e.source = n.id
         WHERE e.target = (SELECT id FROM nodes WHERE rowid=?) AND e.kind='calls'
         ORDER BY n.file_path, n.start_line;`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_get_callees returns all nodes called by node_id.
graph_get_callees :: proc(db: ^GraphDB, node_id: i64) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT DISTINCT ` + NODE_COLS + ` FROM ` + NODE_FROM + `
         JOIN edges e ON e.target = n.id
         WHERE e.source = (SELECT id FROM nodes WHERE rowid=?) AND e.kind='calls'
         ORDER BY n.file_path, n.start_line;`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_get_impact returns all nodes transitively reached from node_id along
// 'calls' edges. depth controls how many hops to follow (default 3).
// Uses a recursive CTE — requires SQLite 3.35+.
graph_get_impact :: proc(db: ^GraphDB, node_id: i64, depth: int) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    sql := fmt.tprintf(`
        WITH RECURSIVE impact(id, depth) AS (
            SELECT target, 1 FROM edges
            WHERE source = (SELECT id FROM nodes WHERE rowid=?) AND kind='calls'
            UNION
            SELECT e.target, i.depth+1
            FROM edges e JOIN impact i ON e.source=i.id
            WHERE i.depth < %d AND e.kind='calls'
        )
        SELECT DISTINCT %s FROM %s JOIN impact im ON n.id = im.id;`, depth, NODE_COLS, NODE_FROM)
    s, ok := sq.db_prepare(db.conn, sql)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_find_file_allocator_vars returns variable nodes in a specific file that
// have memory_role='allocator' (e.g. explicit "name: mem.Allocator" declarations).
graph_find_file_allocator_vars :: proc(db: ^GraphDB, file_path: string) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT ` + NODE_COLS + ` FROM ` + NODE_FROM + `
         WHERE n.kind='variable' AND i.memory_role='allocator' AND n.file_path=?;`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, graph_rel(db, file_path))
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_find_allocators returns all nodes tagged with memory_role='allocator'.
graph_find_allocators :: proc(db: ^GraphDB) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT ` + NODE_COLS + ` FROM ` + NODE_FROM + ` WHERE i.memory_role='allocator';`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_find_all_references returns all edge locations targeting the named symbol.
graph_find_all_references :: proc(db: ^GraphDB, name: string) -> [dynamic]GraphEdgeInfo {
    result := make([dynamic]GraphEdgeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT src.name, tgt.name, e.kind, src.file_path, e.line
         FROM edges e
         JOIN nodes src ON e.source = src.id
         JOIN nodes tgt ON e.target = tgt.id
         WHERE tgt.name=? AND e.kind != 'contains';`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    for sq.stmt_step(&s) {
        rel := sq.stmt_col_text(&s, 3)
        append(&result, GraphEdgeInfo{
            source_name = sq.stmt_col_text(&s, 0),
            target_name = sq.stmt_col_text(&s, 1),
            kind        = sq.stmt_col_text(&s, 2),
            file        = graph_abs(db, rel),
            line        = sq.stmt_col_int(&s, 4),
        })
        delete(rel)
    }
    return result
}

// RenameLocation is a single site where a symbol name must be changed.
RenameLocation :: struct {
    file:   string,
    line:   int,
    kind:   string,  // "declaration" | "call_site"
}

// graph_rename_locations returns all locations (declaration + call sites) for old_name.
graph_rename_locations :: proc(db: ^GraphDB, old_name: string) -> [dynamic]RenameLocation {
    result := make([dynamic]RenameLocation)

    // Declaration site.
    s1, ok1 := sq.db_prepare(db.conn,
        `SELECT file_path, start_line FROM nodes WHERE name=? AND kind IN `+TARGET_KINDS+` LIMIT 1;`)
    if ok1 {
        sq.stmt_bind_text(&s1, 1, old_name)
        if sq.stmt_step(&s1) {
            rel := sq.stmt_col_text(&s1, 0)
            append(&result, RenameLocation{
                file = graph_abs(db, rel),
                line = sq.stmt_col_int(&s1, 1),
                kind = "declaration",
            })
            delete(rel)
        }
        sq.stmt_finalize(&s1)
    }

    // Call / reference sites.
    s2, ok2 := sq.db_prepare(db.conn,
        `SELECT src.file_path, e.line FROM edges e
         JOIN nodes src ON e.source = src.id
         JOIN nodes tgt ON e.target = tgt.id
         WHERE tgt.name=? AND e.kind != 'contains';`)
    if ok2 {
        sq.stmt_bind_text(&s2, 1, old_name)
        for sq.stmt_step(&s2) {
            rel := sq.stmt_col_text(&s2, 0)
            append(&result, RenameLocation{
                file = graph_abs(db, rel),
                line = sq.stmt_col_int(&s2, 1),
                kind = "call_site",
            })
            delete(rel)
        }
        sq.stmt_finalize(&s2)
    }

    return result
}

graph_free_rename_locations :: proc(locs: ^[dynamic]RenameLocation) {
    for l in locs^ { delete(l.file) }
    delete(locs^)
}

// graph_rebuild_fts rebuilds CodeGraph's FTS5 index from the nodes table.
// The schema's triggers keep it current on every insert, so this is only a
// safety net after bulk changes.
graph_rebuild_fts :: proc(db: ^GraphDB) {
    sq.db_exec(db.conn, "INSERT INTO nodes_fts(nodes_fts) VALUES('rebuild');")
}

// graph_search_nodes searches node names using FTS5.
// Returns up to `limit` matching nodes, ranked by FTS relevance.
graph_search_nodes :: proc(db: ^GraphDB, query: string, limit: int) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    sql := fmt.tprintf(
        `SELECT %s FROM nodes_fts f
         JOIN nodes n ON n.rowid = f.rowid
         LEFT JOIN odin_node_info i ON i.node_id = n.id
         WHERE nodes_fts MATCH ? AND n.kind != 'file'
         ORDER BY f.rank LIMIT %d;`, NODE_COLS, limit)
    s, ok := sq.db_prepare(db.conn, sql)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    // FTS5 MATCH pattern: quote the term and prefix-match it.
    safe_query := strings.replace_all(query, `"`, `""`) or_else query
    pattern    := fmt.tprintf(`"%s"*`, safe_query)
    sq.stmt_bind_text(&s, 1, pattern)
    for sq.stmt_step(&s) { append(&result, scan_node_info(db, &s)) }
    return result
}

// graph_insert_enum_member stores one member of an enum node as an `enum_member`
// node contained by the enum, the way CodeGraph models enum members.
graph_insert_enum_member :: proc(db: ^GraphDB, enum_node_id: i64, member_name: string, idx: int, line: int = 0) {
    s, ok := sq.db_prepare(db.conn,
        `SELECT id, qualified_name, file_path, start_line FROM nodes WHERE rowid=?;`)
    if !ok { return }
    enum_text_id: string
    enum_qual:    string
    enum_file:    string
    enum_line := 0
    sq.stmt_bind_i64(&s, 1, enum_node_id)
    if sq.stmt_step(&s) {
        enum_text_id = sq.stmt_col_text(&s, 0)
        enum_qual    = sq.stmt_col_text(&s, 1)
        enum_file    = sq.stmt_col_text(&s, 2)
        enum_line    = sq.stmt_col_int(&s, 3)
    }
    sq.stmt_finalize(&s)
    defer { delete(enum_text_id); delete(enum_qual); delete(enum_file) }
    if enum_text_id == "" { return }

    mline := line if line > 0 else enum_line
    mid   := _node_id(enum_file, "enum_member", fmt.tprintf("%s.%s", enum_qual, member_name), mline, idx)
    ins, ins_ok := sq.db_prepare(db.conn,
        `INSERT OR IGNORE INTO nodes(
            id, kind, name, qualified_name, file_path, language,
            start_line, end_line, start_column, end_column, visibility, is_exported, updated_at)
         VALUES(?, 'enum_member', ?, ?, ?, 'odin', ?, ?, ?, 0, 'public', 1, ?);`)
    if !ins_ok { return }
    sq.stmt_bind_text(&ins, 1, mid)
    sq.stmt_bind_text(&ins, 2, member_name)
    sq.stmt_bind_text(&ins, 3, fmt.tprintf("%s::%s", enum_qual, member_name))
    sq.stmt_bind_text(&ins, 4, enum_file)
    sq.stmt_bind_int(&ins,  5, mline)
    sq.stmt_bind_int(&ins,  6, mline)
    sq.stmt_bind_int(&ins,  7, idx)   // start_column carries declaration order within a line
    sq.stmt_bind_i64(&ins,  8, _now_ms())
    sq.stmt_exec(&ins)
    sq.stmt_finalize(&ins)

    ce, ce_ok := sq.db_prepare(db.conn,
        `INSERT OR IGNORE INTO edges(source, target, kind, line, col) VALUES(?, ?, 'contains', ?, ?);`)
    if ce_ok {
        sq.stmt_bind_text(&ce, 1, enum_text_id)
        sq.stmt_bind_text(&ce, 2, mid)
        sq.stmt_bind_int(&ce,  3, mline)
        sq.stmt_bind_int(&ce,  4, idx)
        sq.stmt_exec(&ce)
        sq.stmt_finalize(&ce)
    }
}

// graph_get_enum_members returns all member names of the enum type named type_name,
// in declaration order. Returns nil if the type is not found or has no members.
graph_get_enum_members :: proc(db: ^GraphDB, type_name: string) -> []string {
    s, ok := sq.db_prepare(db.conn,
        `SELECT m.name FROM nodes e
         JOIN edges c ON c.source = e.id AND c.kind = 'contains'
         JOIN nodes m ON m.id = c.target AND m.kind = 'enum_member'
         WHERE e.name=? AND e.kind='enum'
         ORDER BY m.start_line, m.start_column, m.rowid;`)
    if !ok { return nil }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, type_name)

    members := make([dynamic]string)
    for sq.stmt_step(&s) {
        append(&members, sq.stmt_col_text(&s, 0))
    }
    if len(members) == 0 { delete(members); return nil }
    return members[:]
}

// graph_evict_file removes a file's nodes and everything hanging off them.
// Used during incremental rebuild to clean up deleted or changed files. Edges,
// unresolved references and odin_node_info rows go with their nodes
// (ON DELETE CASCADE).
graph_evict_file :: proc(db: ^GraphDB, file_path: string) {
    rel := graph_rel(db, file_path)
    for sql in ([]string{
        "DELETE FROM nodes WHERE file_path=?;",
        "DELETE FROM unresolved_refs WHERE file_path=?;",
        "DELETE FROM files WHERE path=?;",
    }) {
        s, ok := sq.db_prepare(db.conn, sql)
        if !ok { continue }
        sq.stmt_bind_text(&s, 1, rel)
        sq.stmt_exec(&s)
        sq.stmt_finalize(&s)
    }
}

// graph_known_file_hashes returns a map of absolute path → content_hash for all indexed files.
// Caller owns the map and all strings; free with graph_free_file_hashes.
graph_known_file_hashes :: proc(db: ^GraphDB) -> map[string]string {
    result := make(map[string]string)
    s, ok := sq.db_prepare(db.conn, "SELECT path, content_hash FROM files;")
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    for sq.stmt_step(&s) {
        rel := sq.stmt_col_text(&s, 0)
        v   := sq.stmt_col_text(&s, 1)
        result[graph_abs(db, rel)] = v
        delete(rel)
    }
    return result
}

graph_free_file_hashes :: proc(m: ^map[string]string) {
    for k, v in m^ { delete(k); delete(v) }
    delete(m^)
}

// graph_ensure_dir creates the directory for db_path if it does not exist.
graph_ensure_dir :: proc(db_path: string) -> bool {
    dir := ""
    for i := len(db_path) - 1; i >= 0; i -= 1 {
        if db_path[i] == '/' {
            dir = db_path[:i]
            break
        }
    }
    if dir == "" { return true }
    err := os.make_directory(dir)
    return err == nil || os.is_dir(dir)
}
