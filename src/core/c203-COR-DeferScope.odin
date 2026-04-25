package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C203: Defer scope trap — defer in inner block assigns handle to outer scope
// =============================================================================
// Unlike Go, Odin defer fires at the END OF THE ENCLOSING BLOCK, not the
// procedure. A defer inside an if/for/when/nested-{} block fires when that
// inner block exits.
//
// This rule detects the pattern:
//   outer_struct.field = handle
//   defer resource_close(handle)   ← fires at inner block exit
//   ↳ outer_struct.field is dangling after the block
//
// Detection heuristic: inside an inner block (grandparent ≠ procedure),
// if defer f(x) co-exists with <something>.<field> = x in the same block,
// flag the defer as the source of the trap.
//
// Category: CORRECTNESS — enabled by default
// =============================================================================

C203Rule :: proc() -> Rule {
	return Rule{
		id       = "C203",
		tier     = "correctness",
		category = .CORRECTNESS,
		matcher  = nil,
		message  = c203_message,
		fix_hint = c203_fix_hint,
	}
}

c203_message  :: proc() -> string { return "defer fires at inner block exit — handle assigned to outer scope becomes dangling" }
c203_fix_hint :: proc() -> string { return "Move defer to the outer scope, or avoid storing the resource handle in outer variables" }

c203_run :: proc(file_path: string, root_node: TSNode, file_lines: []string) -> []Diagnostic {
	diagnostics  := make([dynamic]Diagnostic)
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	c203_walk(file_path, root_node, file_lines, suppressions, &diagnostics)
	return diagnostics[:]
}

@(private = "file")
c203_walk :: proc(file_path: string, node: TSNode, lines: []string, suppressions: map[int][]string, out: ^[dynamic]Diagnostic) {
	n := ts_node_child_count(node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(node, i)
		if ts_node_is_null(child) { continue }
		if string(ts_node_type(child)) == "defer_statement" {
			c203_check_defer(file_path, child, lines, suppressions, out)
		}
		c203_walk(file_path, child, lines, suppressions, out)
	}
}

@(private = "file")
c203_check_defer :: proc(file_path: string, defer_node: TSNode, lines: []string, suppressions: map[int][]string, out: ^[dynamic]Diagnostic) {
	// Only flag defer inside an inner block (not the procedure body).
	parent_block := ts_node_parent(defer_node)
	if ts_node_is_null(parent_block) { return }
	if string(ts_node_type(parent_block)) != "block" { return }

	grandparent := ts_node_parent(parent_block)
	if ts_node_is_null(grandparent) { return }
	// If grandparent is 'procedure', this block IS the procedure body — defer is safe there.
	if string(ts_node_type(grandparent)) == "procedure" { return }

	// Extract argument variable names from the deferred call.
	defer_args := c203_extract_args(defer_node, lines)
	defer delete(defer_args)
	if len(defer_args) == 0 { return }

	defer_line := int(ts_node_start_point(defer_node).row)

	// Walk all siblings in same block; look for assignment_statement where
	// the LHS is a member access (contains ".") and the RHS contains a deferred arg.
	block_n := ts_node_child_count(parent_block)
	for i: u32 = 0; i < block_n; i += 1 {
		sibling := ts_node_child(parent_block, i)
		if ts_node_is_null(sibling) { continue }
		if string(ts_node_type(sibling)) != "assignment_statement" { continue }

		sib_line := int(ts_node_start_point(sibling).row)
		if sib_line == defer_line { continue }
		if sib_line < 0 || sib_line >= len(lines) { continue }

		line_text := lines[sib_line]
		eq_idx    := c203_find_plain_assign(line_text)
		if eq_idx < 0 { continue }

		lhs := strings.trim_right(line_text[:eq_idx], " \t")
		rhs := line_text[eq_idx+1:]

		// LHS must be a member access (outer struct field) to flag.
		if !strings.contains(lhs, ".") { continue }

		for arg in defer_args {
			if !c203_rhs_has_ident(rhs, arg) { continue }

			pt        := ts_node_start_point(defer_node)
			diag_line := int(pt.row) + 1
			if is_suppressed("C203", diag_line, suppressions) { break }

			append(out, Diagnostic{
				file      = file_path,
				line      = diag_line,
				column    = int(pt.column) + 1,
				rule_id   = "C203",
				tier      = "correctness",
				message   = fmt.aprintf(
					"defer fires at inner block exit — '%s' is assigned to '%s' which becomes dangling (Odin defer is block-scoped, unlike Go)",
					arg, strings.trim_left(lhs, " \t")),
				has_fix   = true,
				fix       = "Move defer to the outer scope, or avoid storing the resource handle in outer variables",
				diag_type = .VIOLATION,
			})
			break
		}
	}
}

// c203_extract_args returns identifier names passed as arguments to the deferred call.
// Handles both plain calls (close(x)) and qualified calls (os.close(x)).
@(private = "file")
c203_extract_args :: proc(defer_node: TSNode, lines: []string) -> [dynamic]string {
	args := make([dynamic]string)

	n := ts_node_child_count(defer_node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(defer_node, i)
		if ts_node_is_null(child) { continue }

		call_node: TSNode
		switch string(ts_node_type(child)) {
		case "call_expression":
			call_node = child
		case "member_expression":
			// os.close(db) is parsed as member_expression { call_expression }
			cn := ts_node_child_count(child)
			for j: u32 = 0; j < cn; j += 1 {
				cc := ts_node_child(child, j)
				if !ts_node_is_null(cc) && string(ts_node_type(cc)) == "call_expression" {
					call_node = cc
					break
				}
			}
		}

		if ts_node_is_null(call_node) { continue }

		// call_expression children: [function, (, arg1, ,, arg2, )]
		// Skip child[0] (function name), gather identifier children after it.
		call_n := ts_node_child_count(call_node)
		for j: u32 = 1; j < call_n; j += 1 {
			cc := ts_node_child(call_node, j)
			if ts_node_is_null(cc) { continue }
			if string(ts_node_type(cc)) == "identifier" {
				text := naming_extract_text(cc, lines)
				if len(text) > 0 { append(&args, text) }
			}
		}
		break // only process first statement-child of defer
	}
	return args
}

// c203_find_plain_assign returns the index of the `=` in a plain assignment,
// skipping `:=`, `==`, `!=`, `<=`, `>=`. Returns -1 if not found.
@(private = "file")
c203_find_plain_assign :: proc(line: string) -> int {
	for i := 0; i < len(line); i += 1 {
		if line[i] != '=' { continue }
		if i > 0 {
			prev := line[i-1]
			if prev == ':' || prev == '!' || prev == '<' || prev == '>' { continue }
		}
		if i+1 < len(line) && line[i+1] == '=' { continue } // ==
		return i
	}
	return -1
}

// c203_rhs_has_ident checks whether `name` appears as a whole identifier in rhs.
@(private = "file")
c203_rhs_has_ident :: proc(rhs: string, name: string) -> bool {
	if len(name) == 0 || len(rhs) == 0 { return false }
	search := rhs
	offset := 0
	for {
		pos := strings.index(search, name)
		if pos < 0 { return false }
		abs  := offset + pos
		before_ok := abs == 0 || !is_ident_byte(rhs[abs-1])
		after_ok  := abs+len(name) >= len(rhs) || !is_ident_byte(rhs[abs+len(name)])
		if before_ok && after_ok { return true }
		offset += pos + 1
		if offset >= len(rhs) { return false }
		search = rhs[offset:]
	}
}

