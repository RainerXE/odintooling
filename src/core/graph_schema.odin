// graph_schema.odin — the graph database schema: CodeGraph's, plus olt's own tables.
//
// olt's graph database IS a CodeGraph database. ffi/codegraph/schema.sql is
// CodeGraph's schema, vendored unmodified (see ffi/codegraph/README.md for the
// pin and the refresh rule), so any tool that reads a CodeGraph database can read
// the one olt writes. Everything olt knows that CodeGraph does not lives in
// odin_* tables, which CodeGraph never touches.
package core

// CodeGraph's schema, as shipped by the pinned upstream commit.
CODEGRAPH_SCHEMA_SQL :: #load("../../ffi/codegraph/schema.sql", string)

// CODEGRAPH_SCHEMA_VERSION is the upstream CURRENT_SCHEMA_VERSION that
// CODEGRAPH_SCHEMA_SQL corresponds to. schema.sql already contains every
// migration's result, so a fresh database is the script plus a schema_versions
// row for THIS version. Recording a lower version makes CodeGraph re-run
// migrations over columns that already exist ("duplicate column name").
// Updated by scripts/update_codegraph_schema.sh; do not edit by hand.
CODEGRAPH_SCHEMA_VERSION :: 16

// ODIN_ANALYSIS_VERSION is the version of the analysis that fills olt's own tables (ownership,
// roles, packages, imports). Exports are incremental, so a file whose content has not changed
// keeps what an older analysis derived from it; when this number moves, an olt-written graph is
// re-indexed in full instead. Raise it whenever a change alters what the analysis records.
ODIN_ANALYSIS_VERSION :: 7

CODEGRAPH_SCHEMA_VERSION_NOTE :: "Initial schema includes all migrations"

// ODIN_SCHEMA_SQL is olt-only data, keyed by CodeGraph's node id (TEXT).
// ON DELETE CASCADE keeps it in step with the nodes table (needs foreign_keys=ON).
ODIN_SCHEMA_SQL :: `
CREATE TABLE IF NOT EXISTS odin_node_info (
    node_id         TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
    memory_role     TEXT,   -- "allocator" | "deallocator" | "borrower" | "neutral"
    lint_violations TEXT    -- JSON array of rule ids, e.g. '["C001"]'
);
CREATE INDEX IF NOT EXISTS idx_odin_node_info_role ON odin_node_info(memory_role);

-- Procedure groups (f :: proc { f_a, f_b }): the member names a group lists, kept so the
-- group -> member 'references' edges can be rebuilt whenever the members move.
CREATE TABLE IF NOT EXISTS odin_group_member (
    group_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    name     TEXT    NOT NULL,
    line     INTEGER NOT NULL,
    col      INTEGER NOT NULL,
    PRIMARY KEY (group_id, name, line, col)
);

-- Allocation sites (see ownership.odin): every make/new/new_clone and the stdlib calls that
-- allocate, inside a procedure. allocator_kind says whether the memory must be freed by
-- hand: default and param do, temp and custom (an arena, a reassigned context.allocator)
-- are released by their allocator. disposition says where the memory went.
CREATE TABLE IF NOT EXISTS odin_alloc_site (
    proc_id        TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    line           INTEGER NOT NULL,
    col            INTEGER NOT NULL,
    api            TEXT    NOT NULL,   -- make | new | new_clone | mem.alloc | strings.clone | ...
    elem_type      TEXT,               -- the type allocated, as written ('Foo', 'pkg.Foo'); NULL if unknown
    allocator_kind TEXT    NOT NULL,   -- default | temp | param | custom
    allocator_expr TEXT,
    var_name       TEXT,               -- the local the result was bound to; NULL if none
    disposition    TEXT    NOT NULL,   -- freed_deferred | freed | returned | stored | passed | unfreed
    PRIMARY KEY (proc_id, line, col)
);
CREATE INDEX IF NOT EXISTS idx_odin_alloc_site_disp ON odin_alloc_site(disposition, allocator_kind);

-- Per procedure: how many calls to a free-like procedure it makes, and how many allocation
-- sites it contains (what the memory-role guess is built from).
CREATE TABLE IF NOT EXISTS odin_proc_ownership (
    proc_id     TEXT    PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
    free_calls  INTEGER NOT NULL DEFAULT 0,
    alloc_sites INTEGER NOT NULL DEFAULT 0
);

-- Parameters a procedure frees (it takes ownership of the argument): odin_param_sink(proc, 0)
-- says the first parameter of that procedure is released inside it. A caller that passes an
-- allocation there has handed it over, not leaked it.
CREATE TABLE IF NOT EXISTS odin_param_sink (
    proc_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    idx     INTEGER NOT NULL,   -- 0-based position among the parameter names
    PRIMARY KEY (proc_id, idx)
);

-- What a procedure does with the parameters it does not free: it 'kept' one (stored it somewhere that
-- outlives the call, or returned it, so the caller no longer owns it) or only 'read' it (the caller still
-- does). A parameter handed on to something unseen has no row: nothing is claimed about it.
CREATE TABLE IF NOT EXISTS odin_param_effect (
    proc_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    idx     INTEGER NOT NULL,
    effect  TEXT    NOT NULL,   -- kept | read
    PRIMARY KEY (proc_id, idx)
);

-- Which procedure a call-based site (api "name()") called, by identity: two procedures with the same
-- name in different packages are different factories.
CREATE TABLE IF NOT EXISTS odin_site_via (
    proc_id   TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    line      INTEGER NOT NULL,
    col       INTEGER NOT NULL,
    callee_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    PRIMARY KEY (proc_id, line, col)
);

-- The allocator parameters of a procedure and what each defaults to: when a caller passes none,
-- that default is what its result is allocated from ('temp' for allocator := context.temp_allocator).
CREATE TABLE IF NOT EXISTS odin_alloc_param (
    proc_id      TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    default_kind TEXT NOT NULL,   -- default | temp | custom | none (no default value)
    PRIMARY KEY (proc_id, name)
);

-- One row per file: the package it declares. A package is a directory, so (dir, name)
-- is what an import's default name is matched against.
CREATE TABLE IF NOT EXISTS odin_package (
    file_path TEXT PRIMARY KEY REFERENCES files(path) ON DELETE CASCADE,
    dir       TEXT NOT NULL,   -- project-relative directory of the file ('' = project root)
    name      TEXT NOT NULL    -- the name after "package"
);
CREATE INDEX IF NOT EXISTS idx_odin_package_dir ON odin_package(dir, name);

-- One row per import declaration: what a file's qualifiers (the "pkg" in pkg.fn())
-- refer to.
CREATE TABLE IF NOT EXISTS odin_import (
    file_path TEXT    NOT NULL REFERENCES files(path) ON DELETE CASCADE,
    line      INTEGER NOT NULL,
    path      TEXT    NOT NULL,   -- as written: "core:fmt", "../shared"
    alias     TEXT,               -- explicit name in  import alias "path";  NULL = the package's own name
    dir       TEXT,               -- project-relative directory the path names; NULL = outside the project
    PRIMARY KEY (file_path, line, path)
);
`
