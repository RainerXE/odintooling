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
`
