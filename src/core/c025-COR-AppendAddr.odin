// c025-COR-AppendAddr.odin — C025: append(slice, v) missing address-of (go_migration domain).
// In Odin, append takes a pointer to the dynamic array: append(&slice, v).
// The SCM and text-based scanners flag bare append(slice, v) calls.
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C025: append(slice, v) — Missing Address-Of Operator
// =============================================================================
// In Go: `slice = append(slice, v)` returns a new slice assigned back.
// In Odin: `append(&slice, v)` takes a POINTER to the slice and mutates it.
//
// Writing `append(slice, v)` in Odin either fails to compile (if slice is not
// a dynamic array type) or silently does nothing useful.
//
// Auto-fix: prepend `&` to the first argument.
// Category: CORRECTNESS — enabled by default
// =============================================================================

c025_run :: proc(
	file_path:  string,
	root_node:  TSNode,
	file_lines: []string,
	q:          ^CompiledQuery,
) -> []Diagnostic {
	results := run_query(q, root_node, file_lines)
	defer free_query_results(results)

	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer free_suppressions(suppressions)
	diags := make([dynamic]Diagnostic)

	for result in results {
		call_node, ok := result.captures["go_compat_call"]
		if !ok { continue }

		// Only check calls to `append`
		fn_name := c025_fn_name(call_node, file_lines)
		if fn_name != "append" { continue }

		// Check first argument — must start with `&` to be correct
		first_arg := c025_first_arg(call_node)
		if ts_node_is_null(first_arg) { continue }

		// If first arg is a unary_expression with operator &, it's correct
		if string(ts_node_type(first_arg)) == "unary_expression" {
			// Check if the operator is &
			if c025_is_address_of(first_arg, file_lines) { continue }
		}

		// First arg is a plain identifier or expression without & → flag it
		if string(ts_node_type(first_arg)) != "identifier" { continue }

		arg_text := naming_extract_text(first_arg, file_lines)
		if arg_text == "" { continue }

		pt        := ts_node_start_point(call_node)
		diag_line := int(pt.row) + 1
		if is_suppressed("C025", diag_line, suppressions) { continue }

		append(&diags, Diagnostic{
			file      = file_path,
			line      = diag_line,
			column    = int(pt.column) + 1,
			rule_id   = "C025",
			tier      = "correctness",
			message   = fmt.aprintf(
				"'append(%s, ...)' — Odin's append takes a pointer to the slice: use 'append(&%s, ...)'",
				arg_text, arg_text),
			has_fix   = true,
			fix       = fmt.aprintf("Change 'append(%s, ...)' to 'append(&%s, ...)'", arg_text, arg_text),
			diag_type = .VIOLATION,
		})
	}
	return diags[:]
}

@(private = "file")
c025_fn_name :: proc(call_node: TSNode, lines: []string) -> string {
	if ts_node_child_count(call_node) == 0 { return "" }
	fn := ts_node_child(call_node, 0)
	if ts_node_is_null(fn) { return "" }
	if string(ts_node_type(fn)) == "identifier" {
		return naming_extract_text(fn, lines)
	}
	return ""
}

@(private = "file")
c025_first_arg :: proc(call_node: TSNode) -> TSNode {
	n := ts_node_child_count(call_node)
	past_paren := false
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(call_node, i)
		if ts_node_is_null(child) { continue }
		ct := string(ts_node_type(child))
		if ct == "(" { past_paren = true; continue }
		if ct == ")" { break }
		if !past_paren || ct == "," { continue }
		return child // first expression child after (
	}
	return TSNode{}
}

@(private = "file")
c025_is_address_of :: proc(unary_node: TSNode, lines: []string) -> bool {
	// Check if first child of unary_expression is the & operator
	n := ts_node_child_count(unary_node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(unary_node, i)
		if ts_node_is_null(child) { continue }
		if string(ts_node_type(child)) == "&" { return true }
		// also check via source text — the & operator node might have type "&"
		pt  := ts_node_start_point(child)
		row := int(pt.row)
		col := int(pt.column)
		if row < len(lines) && col < len(lines[row]) && lines[row][col] == '&' {
			return true
		}
		break // only check first child
	}
	return false
}

// c025_line_scan is a fast text-based backup detection for append patterns
// that the SCM query may miss (e.g. in complex expressions).
c025_line_scan :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer free_suppressions(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1

		// Quick pre-check
		if !strings.contains(line, "append(") { continue }
		// Skip if already using &
		if strings.contains(line, "append(&") { continue }
		// Skip comments
		if cc := strings.index(line, "//"); cc >= 0 {
			// check if "append(" is before the comment
			ap := strings.index(line, "append(")
			if ap < 0 || ap > cc { continue }
		}

		ap := strings.index(line, "append(")
		if ap < 0 { continue }

		// Word boundary check — don't match "prepend(" or "myappend("
		if ap > 0 && is_ident_byte(line[ap-1]) { continue }

		if is_suppressed("C025", line_num, suppressions) { continue }

		// Extract what follows append(
		after := strings.trim_left(line[ap+len("append("):], " \t")
		if len(after) == 0 || after[0] == '&' { continue }

		// Extract the first arg name for the message
		end := 0
		for end < len(after) && (is_ident_byte(after[end]) || after[end] == '.') { end += 1 }
		first_arg := after[:end]

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line_num,
			column    = ap + 1,
			rule_id   = "C025",
			tier      = "correctness",
			message   = fmt.aprintf(
				"'append(%s, ...)' — Odin's append takes a pointer to the slice: use 'append(&%s, ...)'",
				first_arg, first_arg),
			has_fix   = true,
			fix       = fmt.aprintf("Change to 'append(&%s, ...)'", first_arg),
			diag_type = .VIOLATION,
		})
	}
	return diags[:]
}
