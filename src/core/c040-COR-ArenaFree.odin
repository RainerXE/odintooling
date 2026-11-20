// c040-COR-ArenaFree.odin — C040: manual free of temp/arena memory (requires --export-symbols).
//
// The ownership analysis already records, per allocation, which allocator supplied the
// memory and what became of it. This rule reads that fact back: a delete/free (deferred
// or not) on memory from context.temp_allocator (or from an explicit arena allocator) is
// a no-op. The allocator owns the lifetime, so the cleanup reads as real work but
// releases nothing.
//
// Requires the code graph to be built first (--export-symbols); without a graph the rule
// is silent. Suppress with: // olt:ignore C040
package core

import "core:fmt"
import sq "../../vendor/odin-sqlite3"

// c040_run reports manual frees of memory owned by the temp allocator or an arena.
// `file_path` is the path being linted; `lines` is that file's source split by newline.
c040_run :: proc(file_path: string, db: ^GraphDB, lines: []string) -> []Diagnostic {
	diags := make([dynamic]Diagnostic)
	if db == nil { return diags[:] }

	suppressions := collect_suppressions(1, len(lines), lines)
	defer free_suppressions(suppressions)

	rel := graph_rel(db, file_path)
	s, ok := sq.db_prepare(db.conn, `
		SELECT a.line, a.col, a.allocator_kind, COALESCE(a.allocator_expr,''),
		       COALESCE(a.var_name,''), a.api
		FROM odin_alloc_site a
		JOIN nodes n ON n.id = a.proc_id
		WHERE n.file_path = ?1
		  AND a.disposition IN ('freed','freed_deferred')
		  AND (a.allocator_kind IN ('temp','arena')
		       OR (a.allocator_kind = 'custom'
		           AND lower(COALESCE(a.allocator_expr,'')) LIKE '%arena_allocator%'))
		ORDER BY a.line, a.col;`)
	if !ok { return diags[:] }
	defer sq.stmt_finalize(&s)
	sq.stmt_bind_text(&s, 1, rel)

	for sq.stmt_step(&s) {
		line := sq.stmt_col_int(&s, 0)
		col  := sq.stmt_col_int(&s, 1)
		kind := sq.stmt_col_text(&s, 2)
		expr := sq.stmt_col_text(&s, 3)
		name := sq.stmt_col_text(&s, 4)
		api  := sq.stmt_col_text(&s, 5)
		defer { delete(kind); delete(expr); delete(name); delete(api) }

		if is_suppressed("C040", line, suppressions) { continue }

		what := name if name != "" else api
		msg, fix: string
		if kind == "temp" {
			msg = fmt.aprintf(
				"manual free of '%s' is a no-op — the memory came from context.temp_allocator, which owns the lifetime; remove the cleanup, or allocate from context.allocator",
				what,
			)
			fix = "Remove the free; context.temp_allocator releases this memory wholesale"
		} else {
			msg = fmt.aprintf(
				"manual free of '%s' is a no-op — the memory belongs to an arena (%s), which releases it wholesale; remove the cleanup",
				what, expr,
			)
			fix = "Remove the free; the arena owns the lifetime of this memory"
		}

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line,
			column    = col + 1,
			rule_id   = "C040",
			tier      = "correctness",
			message   = msg,
			has_fix   = true,
			fix       = fix,
			diag_type = .VIOLATION,
		})
	}

	return diags[:]
}
