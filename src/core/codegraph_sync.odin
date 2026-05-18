// codegraph_sync.odin — translates odin_lint_graph.db into a CodeGraph-compatible
// codegraph.db so users with CodeGraph already configured get Odin symbol intelligence
// via the same MCP tools they use for other languages.
package core

import "core:fmt"
import "core:os"
import "core:time"
import sq "../../vendor/odin-sqlite3"

CODEGRAPH_DB_PATH :: ".codegraph/codegraph.db"

// CodeGraph v1 schema.
// Source: https://github.com/colbymchenry/codegraph/blob/main/src/db/schema.sql
CODEGRAPH_SCHEMA :: `
CREATE TABLE IF NOT EXISTS schema_versions (
    version    INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL,
    description TEXT
);
CREATE TABLE IF NOT EXISTS nodes (
    id              TEXT    PRIMARY KEY,
    kind            TEXT    NOT NULL,
    name            TEXT    NOT NULL,
    qualified_name  TEXT    NOT NULL,
    file_path       TEXT    NOT NULL,
    language        TEXT    NOT NULL,
    start_line      INTEGER NOT NULL,
    end_line        INTEGER NOT NULL,
    start_column    INTEGER NOT NULL,
    end_column      INTEGER NOT NULL,
    docstring       TEXT,
    signature       TEXT,
    visibility      TEXT,
    is_exported     INTEGER DEFAULT 0,
    is_async        INTEGER DEFAULT 0,
    is_static       INTEGER DEFAULT 0,
    is_abstract     INTEGER DEFAULT 0,
    decorators      TEXT,
    type_parameters TEXT,
    updated_at      INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS edges (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    source     TEXT    NOT NULL,
    target     TEXT    NOT NULL,
    kind       TEXT    NOT NULL,
    metadata   TEXT,
    line       INTEGER,
    col        INTEGER,
    provenance TEXT,
    FOREIGN KEY (source) REFERENCES nodes(id) ON DELETE CASCADE,
    FOREIGN KEY (target) REFERENCES nodes(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS files (
    path         TEXT    PRIMARY KEY,
    content_hash TEXT    NOT NULL,
    language     TEXT    NOT NULL,
    size         INTEGER NOT NULL,
    modified_at  INTEGER NOT NULL,
    indexed_at   INTEGER NOT NULL,
    node_count   INTEGER DEFAULT 0,
    errors       TEXT
);
CREATE TABLE IF NOT EXISTS unresolved_refs (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    from_node_id   TEXT    NOT NULL,
    reference_name TEXT    NOT NULL,
    reference_kind TEXT    NOT NULL,
    line           INTEGER NOT NULL,
    col            INTEGER NOT NULL,
    candidates     TEXT,
    file_path      TEXT    NOT NULL DEFAULT '',
    language       TEXT    NOT NULL DEFAULT 'unknown',
    FOREIGN KEY (from_node_id) REFERENCES nodes(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS project_metadata (
    key        TEXT    PRIMARY KEY,
    value      TEXT    NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_nodes_kind           ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_nodes_name           ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_qualified_name ON nodes(qualified_name);
CREATE INDEX IF NOT EXISTS idx_nodes_file_path      ON nodes(file_path);
CREATE INDEX IF NOT EXISTS idx_nodes_language       ON nodes(language);
CREATE INDEX IF NOT EXISTS idx_nodes_file_line      ON nodes(file_path, start_line);
CREATE INDEX IF NOT EXISTS idx_nodes_lower_name     ON nodes(lower(name));
CREATE VIRTUAL TABLE IF NOT EXISTS nodes_fts USING fts5(
    id, name, qualified_name, docstring, signature,
    content='nodes', content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS nodes_ai AFTER INSERT ON nodes BEGIN
    INSERT INTO nodes_fts(rowid, id, name, qualified_name, docstring, signature)
    VALUES (NEW.rowid, NEW.id, NEW.name, NEW.qualified_name, NEW.docstring, NEW.signature);
END;
CREATE TRIGGER IF NOT EXISTS nodes_ad AFTER DELETE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, name, qualified_name, docstring, signature)
    VALUES ('delete', OLD.rowid, OLD.id, OLD.name, OLD.qualified_name, OLD.docstring, OLD.signature);
END;
CREATE TRIGGER IF NOT EXISTS nodes_au AFTER UPDATE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, name, qualified_name, docstring, signature)
    VALUES ('delete', OLD.rowid, OLD.id, OLD.name, OLD.qualified_name, OLD.docstring, OLD.signature);
    INSERT INTO nodes_fts(rowid, id, name, qualified_name, docstring, signature)
    VALUES (NEW.rowid, NEW.id, NEW.name, NEW.qualified_name, NEW.docstring, NEW.signature);
END;
CREATE INDEX IF NOT EXISTS idx_edges_kind        ON edges(kind);
CREATE INDEX IF NOT EXISTS idx_edges_source_kind ON edges(source, kind);
CREATE INDEX IF NOT EXISTS idx_edges_target_kind ON edges(target, kind);
CREATE INDEX IF NOT EXISTS idx_files_language    ON files(language);
CREATE INDEX IF NOT EXISTS idx_files_modified_at ON files(modified_at);
CREATE INDEX IF NOT EXISTS idx_unresolved_from_node ON unresolved_refs(from_node_id);
CREATE INDEX IF NOT EXISTS idx_unresolved_name      ON unresolved_refs(reference_name);
CREATE INDEX IF NOT EXISTS idx_unresolved_file_path ON unresolved_refs(file_path);
CREATE INDEX IF NOT EXISTS idx_unresolved_from_name ON unresolved_refs(from_node_id, reference_name);
CREATE INDEX IF NOT EXISTS idx_edges_provenance     ON edges(provenance);
`

CodegraphSyncResult :: struct {
    nodes_written: int,
    edges_written: int,
    files_written: int,
    db_path:       string,
    ok:            bool,
}

// codegraph_sync_from_db reads odin_lint_graph.db and writes a CodeGraph-compatible
// codegraph.db. Full rebuild on each call — incremental logic lives upstream in
// export_symbols, so our source DB is already up to date when this runs.
codegraph_sync_from_db :: proc(
    src_path: string = GRAPH_DB_PATH,
    dst_path: string = CODEGRAPH_DB_PATH,
) -> CodegraphSyncResult {
    result := CodegraphSyncResult{db_path = dst_path}

    if !graph_ensure_dir(dst_path) {
        fmt.eprintfln("codegraph-sync: cannot create directory for %s", dst_path)
        return result
    }
    _cg_write_gitignore(dst_path)

    src, src_ok := sq.db_open(src_path)
    if !src_ok {
        fmt.eprintfln("codegraph-sync: cannot open source db %s", src_path)
        return result
    }
    defer sq.db_close(src)

    _ = os.remove(dst_path)
    dst, dst_ok := sq.db_open(dst_path)
    if !dst_ok {
        fmt.eprintfln("codegraph-sync: cannot create %s", dst_path)
        return result
    }
    defer sq.db_close(dst)

    if !sq.db_exec_script(dst, CODEGRAPH_SCHEMA) {
        fmt.eprintfln("codegraph-sync: schema init failed: %s", sq.db_errmsg(dst))
        return result
    }

    now_ms := i64(time.now()._nsec / 1_000_000)
    sq.db_exec(dst, "BEGIN;")

    // schema_versions
    {
        sv, sv_ok := sq.db_prepare(dst,
            `INSERT OR IGNORE INTO schema_versions(version,applied_at,description) VALUES(1,?,'Initial schema');`)
        if sv_ok {
            sq.stmt_bind_i64(&sv, 1, now_ms)
            sq.stmt_exec(&sv)
            sq.stmt_finalize(&sv)
        }
    }

    // Nodes
    {
        ns, ns_ok := sq.db_prepare(src,
            `SELECT id, name, COALESCE(qualified_name,name), kind, file,
                    line, COALESCE(signature,''), is_exported
             FROM nodes;`)
        if !ns_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&ns)

        ni, ni_ok := sq.db_prepare(dst,
            `INSERT OR IGNORE INTO nodes
                 (id, kind, name, qualified_name, file_path, language,
                  start_line, end_line, start_column, end_column,
                  signature, visibility, is_exported,
                  is_async, is_static, is_abstract, updated_at)
             VALUES (?,?,?,?,?,'odin',?,?,0,0,?,?,?,0,0,0,?);`)
        if !ni_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&ni)

        for sq.stmt_step(&ns) {
            src_id      := sq.stmt_col_i64(&ns, 0)
            name        := sq.stmt_col_text(&ns, 1)
            qualified   := sq.stmt_col_text(&ns, 2)
            kind        := sq.stmt_col_text(&ns, 3)
            file        := sq.stmt_col_text(&ns, 4)
            line        := sq.stmt_col_int(&ns, 5)
            sig         := sq.stmt_col_text(&ns, 6)
            is_exported := sq.stmt_col_int(&ns, 7)

            cg_id      := fmt.tprintf("odin:%d", src_id)
            visibility := "public" if is_exported != 0 else "private"

            sq.stmt_reset(&ni)
            sq.stmt_bind_text(&ni, 1,  cg_id)
            sq.stmt_bind_text(&ni, 2,  kind)
            sq.stmt_bind_text(&ni, 3,  name)
            sq.stmt_bind_text(&ni, 4,  qualified)
            sq.stmt_bind_text(&ni, 5,  file)
            sq.stmt_bind_int(&ni,  6,  line)
            sq.stmt_bind_int(&ni,  7,  line)
            sq.stmt_bind_text(&ni, 8,  sig)
            sq.stmt_bind_text(&ni, 9,  visibility)
            sq.stmt_bind_int(&ni,  10, is_exported)
            sq.stmt_bind_i64(&ni,  11, now_ms)
            sq.stmt_exec(&ni)
            result.nodes_written += 1

            delete(name); delete(qualified); delete(kind); delete(file); delete(sig)
        }
    }

    // Edges
    {
        es, es_ok := sq.db_prepare(src, `SELECT source_id, target_id, kind, line FROM edges;`)
        if !es_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&es)

        ei, ei_ok := sq.db_prepare(dst,
            `INSERT OR IGNORE INTO edges(source, target, kind, line, col) VALUES(?,?,?,?,0);`)
        if !ei_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&ei)

        for sq.stmt_step(&es) {
            src_id := sq.stmt_col_i64(&es, 0)
            tgt_id := sq.stmt_col_i64(&es, 1)
            kind   := sq.stmt_col_text(&es, 2)
            line   := sq.stmt_col_int(&es, 3)

            sq.stmt_reset(&ei)
            sq.stmt_bind_text(&ei, 1, fmt.tprintf("odin:%d", src_id))
            sq.stmt_bind_text(&ei, 2, fmt.tprintf("odin:%d", tgt_id))
            sq.stmt_bind_text(&ei, 3, kind)
            sq.stmt_bind_int(&ei,  4, line)
            sq.stmt_exec(&ei)
            result.edges_written += 1

            delete(kind)
        }
    }

    // Files — node_count derived from the already-inserted nodes in dst.
    {
        fs, fs_ok := sq.db_prepare(src, `SELECT path, content_hash, indexed_at FROM files;`)
        if !fs_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&fs)

        fi, fi_ok := sq.db_prepare(dst,
            `INSERT OR REPLACE INTO files(path, content_hash, language, size,
                                          modified_at, indexed_at, node_count)
             SELECT ?, ?, 'odin', 0, ?, ?, COUNT(n.id) FROM nodes n WHERE n.file_path=?;`)
        if !fi_ok { sq.db_exec(dst, "ROLLBACK;"); return result }
        defer sq.stmt_finalize(&fi)

        for sq.stmt_step(&fs) {
            path       := sq.stmt_col_text(&fs, 0)
            hash       := sq.stmt_col_text(&fs, 1)
            indexed_at := sq.stmt_col_i64(&fs, 2)

            sq.stmt_reset(&fi)
            sq.stmt_bind_text(&fi, 1, path)
            sq.stmt_bind_text(&fi, 2, hash)
            sq.stmt_bind_i64(&fi,  3, indexed_at)
            sq.stmt_bind_i64(&fi,  4, indexed_at)
            sq.stmt_bind_text(&fi, 5, path)
            sq.stmt_exec(&fi)
            result.files_written += 1

            delete(path); delete(hash)
        }
    }

    // Unresolved refs
    {
        ur_s, ur_ok := sq.db_prepare(src,
            `SELECT source_id, target_name, kind, file, line FROM unresolved_refs;`)
        if ur_ok {
            defer sq.stmt_finalize(&ur_s)
            ur_i, ur_i_ok := sq.db_prepare(dst,
                `INSERT INTO unresolved_refs
                     (from_node_id, reference_name, reference_kind, line, col, file_path, language)
                 VALUES(?,?,?,?,0,?,'odin');`)
            if ur_i_ok {
                defer sq.stmt_finalize(&ur_i)
                for sq.stmt_step(&ur_s) {
                    src_id      := sq.stmt_col_i64(&ur_s, 0)
                    target_name := sq.stmt_col_text(&ur_s, 1)
                    kind        := sq.stmt_col_text(&ur_s, 2)
                    file        := sq.stmt_col_text(&ur_s, 3)
                    line        := sq.stmt_col_int(&ur_s, 4)

                    sq.stmt_reset(&ur_i)
                    sq.stmt_bind_text(&ur_i, 1, fmt.tprintf("odin:%d", src_id))
                    sq.stmt_bind_text(&ur_i, 2, target_name)
                    sq.stmt_bind_text(&ur_i, 3, kind)
                    sq.stmt_bind_int(&ur_i,  4, line)
                    sq.stmt_bind_text(&ur_i, 5, file)
                    sq.stmt_exec(&ur_i)

                    delete(target_name); delete(kind); delete(file)
                }
            }
        }
    }

    // Project metadata
    _cg_meta_kv(dst, "indexer",         "odin-lint",  now_ms)
    _cg_meta_kv(dst, "indexer_version", OLT_VERSION,  now_ms)
    _cg_meta_kv(dst, "language",        "odin",       now_ms)

    sq.db_exec(dst, "COMMIT;")
    result.ok = true
    return result
}

// _cg_write_gitignore writes .codegraph/.gitignore if it does not already exist.
// Matches the file CodeGraph itself would create, ensuring *.db files are not committed.
@(private)
_cg_write_gitignore :: proc(db_path: string) {
    dir := filepath_dir(db_path)
    if dir == "" || dir == "." { dir = ".codegraph" }
    gi_path := fmt.tprintf("%s/.gitignore", dir)
    if os.is_file(gi_path) { return }
    content := "# CodeGraph data files — local to each machine, do not commit\n*.db\n*.db-wal\n*.db-shm\ncache/\n*.log\n.dirty\n"
    _ = os.write_entire_file(gi_path, transmute([]u8)string(content))
}

@(private)
_cg_meta_kv :: proc(db: ^sq.Connection, key, value: string, ts: i64) {
    s, ok := sq.db_prepare(db,
        `INSERT OR REPLACE INTO project_metadata(key,value,updated_at) VALUES(?,?,?);`)
    if !ok { return }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, key)
    sq.stmt_bind_text(&s, 2, value)
    sq.stmt_bind_i64(&s,  3, ts)
    sq.stmt_exec(&s)
}
