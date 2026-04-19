package core

import "core:fmt"
import "core:os"
import "core:strings"
import sq "../../vendor/odin-sqlite3"

// =============================================================================
// Schema
// =============================================================================

GRAPH_SCHEMA :: `
CREATE TABLE IF NOT EXISTS nodes (
    id             INTEGER PRIMARY KEY,
    name           TEXT    NOT NULL,
    qualified_name TEXT,
    kind           TEXT    NOT NULL,  -- "proc"|"type"|"constant"|"variable"|"import"
    language       TEXT    NOT NULL DEFAULT 'odin',
    file           TEXT    NOT NULL,
    line           INTEGER NOT NULL DEFAULT 0,
    signature      TEXT,
    is_exported    INTEGER NOT NULL DEFAULT 1,
    memory_role    TEXT,              -- "allocator"|"deallocator"|"borrower"|"neutral"
    lint_violations TEXT              -- JSON array of rule IDs, e.g. '["C001"]'
);

CREATE TABLE IF NOT EXISTS edges (
    id        INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES nodes(id),
    target_id INTEGER NOT NULL REFERENCES nodes(id),
    kind      TEXT    NOT NULL,  -- "calls"|"references"|"imports"|"ffi_call"
    line      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS files (
    path         TEXT PRIMARY KEY,
    content_hash TEXT NOT NULL,
    indexed_at   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS unresolved_refs (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER REFERENCES nodes(id),
    target_name TEXT    NOT NULL,
    kind        TEXT    NOT NULL,
    file        TEXT,
    line        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_nodes_name    ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_file    ON nodes(file);
CREATE INDEX IF NOT EXISTS idx_nodes_kind    ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_edges_source  ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target  ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_kind    ON edges(kind);
`

// =============================================================================
// GraphDB
// =============================================================================

GraphDB :: struct {
    conn: ^sq.Connection,
    path: string,
}

GraphNodeInfo :: struct {
    id:           i64,
    name:         string,
    kind:         string,
    file:         string,
    line:         int,
    memory_role:  string,
    lint_violations: string,
    signature:    string,
}

GraphEdgeInfo :: struct {
    source_name: string,
    target_name: string,
    kind:        string,
    file:        string,
    line:        int,
}

// graph_open opens (or creates) the graph database at path.
graph_open :: proc(path: string) -> (db: ^GraphDB, ok: bool) {
    conn, conn_ok := sq.db_open(path)
    if !conn_ok { return nil, false }
    db = new(GraphDB)
    db.conn = conn
    db.path = strings.clone(path)
    if !sq.db_exec_script(db.conn, GRAPH_SCHEMA) {
        sq.db_close(conn)
        free(db)
        return nil, false
    }
    return db, true
}

// graph_close closes and frees the database.
graph_close :: proc(db: ^GraphDB) {
    if db == nil { return }
    sq.db_close(db.conn)
    delete(db.path)
    free(db)
}

// graph_clear wipes all data (used before a full re-index).
graph_clear :: proc(db: ^GraphDB) {
    sq.db_exec(db.conn, "DELETE FROM unresolved_refs;")
    sq.db_exec(db.conn, "DELETE FROM edges;")
    sq.db_exec(db.conn, "DELETE FROM nodes;")
    sq.db_exec(db.conn, "DELETE FROM files;")
}

// =============================================================================
// Insert helpers
// =============================================================================

// graph_insert_node inserts a node and returns its rowid.
// Returns -1 on failure.
graph_insert_node :: proc(
    db:           ^GraphDB,
    name:         string,
    qualified:    string,
    kind:         string,
    file:         string,
    line:         int,
    signature:    string,
    is_exported:  bool,
) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        "INSERT INTO nodes(name,qualified_name,kind,file,line,signature,is_exported) VALUES(?,?,?,?,?,?,?);")
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)

    sq.stmt_bind_text(&s, 1, name)
    sq.stmt_bind_text(&s, 2, qualified)
    sq.stmt_bind_text(&s, 3, kind)
    sq.stmt_bind_text(&s, 4, file)
    sq.stmt_bind_int(&s, 5, line)
    sq.stmt_bind_text(&s, 6, signature)
    sq.stmt_bind_int(&s, 7, 1 if is_exported else 0)

    if !sq.stmt_exec(&s) { return -1 }
    return sq.db_last_id(db.conn)
}

// graph_insert_edge inserts a directed edge between two nodes.
graph_insert_edge :: proc(db: ^GraphDB, source_id, target_id: i64, kind: string, line: int) {
    s, ok := sq.db_prepare(db.conn,
        "INSERT OR IGNORE INTO edges(source_id,target_id,kind,line) VALUES(?,?,?,?);")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, source_id)
    sq.stmt_bind_i64(&s, 2, target_id)
    sq.stmt_bind_text(&s, 3, kind)
    sq.stmt_bind_int(&s, 4, line)
    sq.stmt_exec(&s)
}

// graph_insert_file records a file with its content hash.
graph_insert_file :: proc(db: ^GraphDB, path: string, hash: string, ts: i64) {
    s, ok := sq.db_prepare(db.conn,
        "INSERT OR REPLACE INTO files(path,content_hash,indexed_at) VALUES(?,?,?);")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, path)
    sq.stmt_bind_text(&s, 2, hash)
    sq.stmt_bind_i64(&s, 3, ts)
    sq.stmt_exec(&s)
}

// graph_insert_unresolved stores a call site whose callee could not be resolved.
graph_insert_unresolved :: proc(db: ^GraphDB, source_id: i64, target_name, kind, file: string, line: int) {
    s, ok := sq.db_prepare(db.conn,
        "INSERT INTO unresolved_refs(source_id,target_name,kind,file,line) VALUES(?,?,?,?,?);")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, source_id)
    sq.stmt_bind_text(&s, 2, target_name)
    sq.stmt_bind_text(&s, 3, kind)
    sq.stmt_bind_text(&s, 4, file)
    sq.stmt_bind_int(&s, 5, line)
    sq.stmt_exec(&s)
}

// graph_update_memory_role tags a node with its inferred memory role.
graph_update_memory_role :: proc(db: ^GraphDB, node_id: i64, role: string) {
    s, ok := sq.db_prepare(db.conn, "UPDATE nodes SET memory_role=? WHERE id=?;")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, role)
    sq.stmt_bind_i64(&s, 2, node_id)
    sq.stmt_exec(&s)
}

// graph_update_violations attaches a JSON array of lint rule IDs to a node.
graph_update_violations :: proc(db: ^GraphDB, node_id: i64, violations_json: string) {
    s, ok := sq.db_prepare(db.conn, "UPDATE nodes SET lint_violations=? WHERE id=?;")
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, violations_json)
    sq.stmt_bind_i64(&s, 2, node_id)
    sq.stmt_exec(&s)
}

// =============================================================================
// Lookup helpers
// =============================================================================

// graph_find_node returns the id of the first node matching name (exact).
// Returns -1 if not found.
graph_find_node :: proc(db: ^GraphDB, name: string) -> i64 {
    s, ok := sq.db_prepare(db.conn, "SELECT id FROM nodes WHERE name=? LIMIT 1;")
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// graph_find_node_in_file returns the id of a node matching name within a specific file.
graph_find_node_in_file :: proc(db: ^GraphDB, name: string, file: string) -> i64 {
    s, ok := sq.db_prepare(db.conn, "SELECT id FROM nodes WHERE name=? AND file=? LIMIT 1;")
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    sq.stmt_bind_text(&s, 2, file)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// =============================================================================
// Query helpers (MCP tool backing)
// =============================================================================

@(private)
scan_node_info :: proc(s: ^sq.Stmt) -> GraphNodeInfo {
    return GraphNodeInfo{
        id          = sq.stmt_col_i64(s, 0),
        name        = sq.stmt_col_text(s, 1),
        kind        = sq.stmt_col_text(s, 2),
        file        = sq.stmt_col_text(s, 3),
        line        = sq.stmt_col_int(s, 4),
        memory_role = sq.stmt_col_text(s, 5),
        lint_violations = sq.stmt_col_text(s, 6),
        signature   = sq.stmt_col_text(s, 7),
    }
}

// graph_get_node returns a single node by name.
graph_get_node :: proc(db: ^GraphDB, name: string) -> (GraphNodeInfo, bool) {
    s, ok := sq.db_prepare(db.conn,
        `SELECT id,name,kind,file,line,memory_role,lint_violations,signature
         FROM nodes WHERE name=? LIMIT 1;`)
    if !ok { return {}, false }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    if sq.stmt_step(&s) { return scan_node_info(&s), true }
    return {}, false
}

// graph_get_callers returns all proc nodes that have a 'calls' edge to node_id.
graph_get_callers :: proc(db: ^GraphDB, node_id: i64) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT n.id,n.name,n.kind,n.file,n.line,n.memory_role,n.lint_violations,n.signature
         FROM nodes n JOIN edges e ON e.source_id=n.id
         WHERE e.target_id=? AND e.kind='calls';`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(&s)) }
    return result
}

// graph_get_callees returns all nodes called by node_id.
graph_get_callees :: proc(db: ^GraphDB, node_id: i64) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT n.id,n.name,n.kind,n.file,n.line,n.memory_role,n.lint_violations,n.signature
         FROM nodes n JOIN edges e ON e.target_id=n.id
         WHERE e.source_id=? AND e.kind='calls';`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(&s)) }
    return result
}

// graph_get_impact returns all nodes transitively affected by changing node_id.
// depth controls how many hops to follow (default 3).
// Uses a recursive CTE — requires SQLite 3.35+.
graph_get_impact :: proc(db: ^GraphDB, node_id: i64, depth: int) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    sql := fmt.tprintf(`
        WITH RECURSIVE impact(id, depth) AS (
            SELECT target_id, 1 FROM edges WHERE source_id=? AND kind='calls'
            UNION
            SELECT e.target_id, i.depth+1
            FROM edges e JOIN impact i ON e.source_id=i.id
            WHERE i.depth < %d AND e.kind='calls'
        )
        SELECT DISTINCT n.id,n.name,n.kind,n.file,n.line,n.memory_role,n.lint_violations,n.signature
        FROM nodes n JOIN impact i ON n.id=i.id;`, depth)
    s, ok := sq.db_prepare(db.conn, sql)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) { append(&result, scan_node_info(&s)) }
    return result
}

// graph_find_allocators returns all nodes tagged with memory_role='allocator'.
graph_find_allocators :: proc(db: ^GraphDB) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT id,name,kind,file,line,memory_role,lint_violations,signature
         FROM nodes WHERE memory_role='allocator';`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    for sq.stmt_step(&s) { append(&result, scan_node_info(&s)) }
    return result
}

// graph_find_all_references returns all edge locations targeting the named symbol.
graph_find_all_references :: proc(db: ^GraphDB, name: string) -> [dynamic]GraphEdgeInfo {
    result := make([dynamic]GraphEdgeInfo)
    s, ok := sq.db_prepare(db.conn,
        `SELECT src.name, tgt.name, e.kind, src.file, e.line
         FROM edges e
         JOIN nodes src ON e.source_id = src.id
         JOIN nodes tgt ON e.target_id = tgt.id
         WHERE tgt.name=?;`)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    for sq.stmt_step(&s) {
        append(&result, GraphEdgeInfo{
            source_name = sq.stmt_col_text(&s, 0),
            target_name = sq.stmt_col_text(&s, 1),
            kind        = sq.stmt_col_text(&s, 2),
            file        = sq.stmt_col_text(&s, 3),
            line        = sq.stmt_col_int(&s, 4),
        })
    }
    return result
}

// graph_search_nodes does a prefix-match search on node names.
// FTS5 full-text search is planned for a later milestone; this uses LIKE for now.
graph_search_nodes :: proc(db: ^GraphDB, query: string, limit: int) -> [dynamic]GraphNodeInfo {
    result := make([dynamic]GraphNodeInfo)
    sql := fmt.tprintf(
        `SELECT id,name,kind,file,line,memory_role,lint_violations,signature
         FROM nodes WHERE name LIKE ? LIMIT %d;`, limit)
    s, ok := sq.db_prepare(db.conn, sql)
    if !ok { return result }
    defer sq.stmt_finalize(&s)
    pattern := fmt.tprintf("%%%s%%", query)
    sq.stmt_bind_text(&s, 1, pattern)
    for sq.stmt_step(&s) { append(&result, scan_node_info(&s)) }
    return result
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
