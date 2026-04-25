package core

import "core:fmt"
import "core:strings"
import sq "../../vendor/odin-sqlite3"

// =============================================================================
// C014: Private proc declared but never called  (opt-in, project-wide)
// =============================================================================
//
// Fires when a proc marked @(private) or @(private="file") has no incoming
// 'calls' edges in the code graph — meaning nothing in the entire project
// calls it. These are dead code candidates safe to delete.
//
// Requires the code graph to be built first (--export-symbols).
// Enabled via [domains] dead_code = true in olt.toml.
//
// Category: DEAD CODE (info tier, opt-in)
// =============================================================================

// c014_query_dead_procs queries the graph for private procs with zero callers.
// Returns a slice of Diagnostics; caller is responsible for deleting them.
c014_query_dead_procs :: proc(db: ^GraphDB) -> []Diagnostic {
    diags := make([dynamic]Diagnostic)

    s, ok := sq.db_prepare(db.conn, `
        SELECT n.name, n.file, n.line
        FROM nodes n
        WHERE n.kind = 'proc'
          AND n.is_exported = 0
          AND NOT EXISTS (
              SELECT 1 FROM edges e
              WHERE e.target_id = n.id AND e.kind = 'calls'
          )
        ORDER BY n.file, n.line;`)
    if !ok { return diags[:] }
    defer sq.stmt_finalize(&s)

    for sq.stmt_step(&s) {
        name := strings.clone(sq.stmt_col_text(&s, 0))
        file := strings.clone(sq.stmt_col_text(&s, 1))
        line := sq.stmt_col_int(&s, 2)

        append(&diags, Diagnostic{
            file      = file,
            line      = line,
            column    = 1,
            rule_id   = "C014",
            tier      = "dead_code",
            message   = fmt.aprintf(
                "@(private) proc '%s' is never called — consider removing it",
                name,
            ),
            has_fix   = true,
            fix       = fmt.aprintf("Delete unused proc '%s'", name),
            diag_type = .INFO,
        })
    }

    return diags[:]
}
