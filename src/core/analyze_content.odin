package core

import "core:strings"

// =============================================================================
// analyze_content — in-memory lint entry point
// =============================================================================
//
// Runs all enabled rules (C001–C011) against source text already in memory.
// Unlike analyze_file, no disk I/O is performed.
//
// Used by:
//   - plugin_main.odin (_plugin_run_rules delegates here)
//   - src/mcp tool_lint.odin (lint_snippet tool)
//
// Parameters:
//   file_path  — used only for Diagnostic.file labelling (need not exist on disk)
//   content    — full UTF-8 source text
//   ts         — initialised tree-sitter parser (reused across calls)
//   diags      — output slice; caller owns and must delete
// =============================================================================

analyze_content :: proc(
	file_path: string,
	content:   string,
	ts:        ^TreeSitterASTParser,
	diags:     ^[dynamic]Diagnostic,
) {
	lines := strings.split(content, "\n")
	defer delete(lines)

	// ── C001: Memory allocation without defer free (AST walker) ──────────────
	ast_root, ast_ok := parseToAST(ts.adapter, content)
	if ast_ok {
		for d in dedupDiagnostics(c001_matcher(file_path, &ast_root, lines)) {
			if d.diag_type != .NONE && d.diag_type != .INTERNAL_ERROR {
				append(diags, d)
			}
		}
	}

	// ── SCM-based rules: parse tree-sitter tree once, run multiple queries ────
	tree, tree_ok := parseSource(ts.adapter.parser, ts.adapter.language, content)
	if !tree_ok {
		return
	}
	defer ts_tree_delete(tree)

	root := getRootNode(tree)
	if ts_node_is_null(root) {
		return
	}

	// C002: Double-free / use-after-free detection
	{
		q, q_ok := load_query_src(ts.adapter.language, MEMORY_SAFETY_SCM, "memory_safety.scm")
		if q_ok {
			for d in dedupDiagnostics(c002_scm_matcher(file_path, root, lines, &q)) {
				append(diags, d)
			}
			unload_query(&q)
		}
	}

	// C003 + C007 + C016 + C017: Naming conventions (shared SCM pass)
	{
		q, q_ok := load_query_src(ts.adapter.language, NAMING_RULES_SCM, "naming_rules.scm")
		if q_ok {
			for d in dedupDiagnostics(naming_scm_run(file_path, root, lines, &q)) {
				append(diags, d)
			}
			unload_query(&q)
		}
	}

	// C009 + C010: Odin 2026 migration helpers
	{
		q, q_ok := load_query_src(ts.adapter.language, ODIN2026_SCM, "odin2026_migration.scm")
		if q_ok {
			for d in dedupDiagnostics(c009_scm_run(file_path, root, lines, &q)) {
				append(diags, d)
			}
			for d in dedupDiagnostics(c010_scm_run(file_path, root, lines, &q)) {
				append(diags, d)
			}
			unload_query(&q)
		}
	}

	// C011: FFI resource safety
	{
		q, q_ok := load_query_src(ts.adapter.language, FFI_SAFETY_SCM, "ffi_safety.scm")
		if q_ok {
			for d in dedupDiagnostics(c011_scm_run(file_path, root, lines, &q)) {
				append(diags, d)
			}
			unload_query(&q)
		}
	}
}
