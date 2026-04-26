// c202-COR-SwitchExhaust.odin — C202: non-exhaustive switch on enum (requires --export-symbols).
// Consults the graph DB enum_members table to check that every enum case is handled;
// skips #partial switch and switches where the enum type cannot be resolved.
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C202: Switch exhaustiveness — enum switch missing cases
// =============================================================================
// Detects switch statements on enum-typed variables that do not cover all
// enum members. Only fires when:
//   1. The switch condition is a plain identifier
//   2. The variable's type is found via local declaration text scan
//   3. The type name has enum members in the graph DB
//   4. At least one member is not covered by any case label
//
// Respected opt-outs:
//   #partial switch — Odin's explicit "I know this is incomplete" marker
//   case _:         — wildcard case covers all remaining values
//
// False-positive safety: silently skips when type cannot be determined or
// is not in the graph. Never fires on non-enum types.
//
// Requires graph DB for enum member lookup — wire via TypeResolveContext.
// Category: CORRECTNESS — enabled by default (no false positives on unknown types)
// =============================================================================

c202_rule :: proc() -> Rule {
	return Rule{
		id       = "C202",
		tier     = "correctness",
		category = .CORRECTNESS,
		matcher  = nil,
		message  = c202_message,
		fix_hint = c202_fix_hint,
	}
}

c202_message  :: proc() -> string { return "Switch on enum value is not exhaustive — one or more cases missing" }
c202_fix_hint :: proc() -> string { return "Add the missing cases or use '#partial switch' to allow incomplete switches" }

c202_run :: proc(file_path: string, root_node: TSNode, file_lines: []string, db: ^GraphDB) -> []Diagnostic {
	if db == nil { return nil }
	diagnostics  := make([dynamic]Diagnostic)
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	c202_walk(file_path, root_node, file_lines, suppressions, db, &diagnostics)
	return diagnostics[:]
}

@(private = "file")
c202_walk :: proc(file_path: string, node: TSNode, lines: []string, suppressions: map[int][]string, db: ^GraphDB, out: ^[dynamic]Diagnostic) {
	n := ts_node_child_count(node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(node, i)
		if ts_node_is_null(child) { continue }
		if string(ts_node_type(child)) == "switch_statement" {
			c202_check_switch(file_path, child, lines, suppressions, db, out)
		}
		c202_walk(file_path, child, lines, suppressions, db, out)
	}
}

@(private = "file")
c202_check_switch :: proc(file_path: string, switch_node: TSNode, lines: []string, suppressions: map[int][]string, db: ^GraphDB, out: ^[dynamic]Diagnostic) {
	// #partial switch — user explicitly acknowledges incompleteness
	if c202_has_partial(switch_node, lines) { return }

	// Extract the condition identifier name (e.g., `x` in `switch x {`)
	cond_name := c202_condition_ident(switch_node, lines)
	if cond_name == "" { return }

	// Find the variable's declared type by scanning preceding lines
	switch_line := int(ts_node_start_point(switch_node).row)
	type_name   := c202_find_var_type(lines, cond_name, switch_line)
	if type_name == "" { return }

	// Look up enum members in graph
	members := graph_get_enum_members(db, type_name)
	if len(members) == 0 { return }
	defer { for m in members { delete(m) }; delete(members) }

	// Collect covered case labels from the switch body
	covered    := c202_covered_cases(switch_node, lines)
	defer delete(covered)

	// Wildcard `case _:` covers everything
	if "_" in covered { return }

	// Find missing members
	missing := make([dynamic]string, context.temp_allocator)
	for m in members {
		if m not_in covered { append(&missing, m) }
	}
	if len(missing) == 0 { return }

	pt        := ts_node_start_point(switch_node)
	diag_line := int(pt.row) + 1
	if is_suppressed("C202", diag_line, suppressions) { return }

	missing_str := strings.join(missing[:], ", ", context.temp_allocator)
	append(out, Diagnostic{
		file      = file_path,
		line      = diag_line,
		column    = int(pt.column) + 1,
		rule_id   = "C202",
		tier      = "correctness",
		message   = fmt.aprintf("switch on '%s' (%s) is not exhaustive — missing: %s", cond_name, type_name, missing_str),
		has_fix   = true,
		fix       = "Add the missing cases, add 'case _:' for a default, or use '#partial switch'",
		diag_type = .VIOLATION,
	})
}

// c202_has_partial returns true if the switch is prefixed with #partial.
@(private = "file")
c202_has_partial :: proc(switch_node: TSNode, lines: []string) -> bool {
	pt := ts_node_start_point(switch_node)
	if int(pt.row) >= len(lines) { return false }
	return strings.contains(lines[pt.row], "#partial")
}

// c202_condition_ident extracts the identifier being switched on.
// Returns "" for non-identifier conditions (type switches, expressions, etc.).
@(private = "file")
c202_condition_ident :: proc(switch_node: TSNode, lines: []string) -> string {
	n := ts_node_child_count(switch_node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(switch_node, i)
		if ts_node_is_null(child) { continue }
		if string(ts_node_type(child)) == "identifier" {
			return naming_extract_text(child, lines)
		}
	}
	return ""
}

// c202_find_var_type scans lines[0:switch_line] for `var_name: TypeName`
// and returns TypeName, or "" if not found. Only matches explicit type
// annotations (not := inferred assignments).
// Scans ALL occurrences of var_name on each line (not just the first)
// to handle proc parameters like `proc(c: Color)` where `c` also appears
// in `handle_color` earlier on the same line.
@(private = "file")
c202_find_var_type :: proc(lines: []string, var_name: string, switch_line: int) -> string {
	search_from  := min(switch_line, len(lines)-1)
	search_limit := max(0, search_from - 50) // look back at most 50 lines
	for i := search_from; i >= search_limit; i -= 1 {
		line  := lines[i]
		offset := 0
		for offset < len(line) {
			pos := strings.index(line[offset:], var_name)
			if pos < 0 { break }
			abs  := offset + pos
			offset = abs + 1 // advance past this occurrence for next iteration

			// Word-boundary before: char before must not be an ident char
			if abs > 0 && is_ident_byte(line[abs-1]) { continue }

			// What follows the variable name?
			after := abs + len(var_name)
			rest  := strings.trim_left(line[after:], " \t")
			if len(rest) == 0 || rest[0] != ':' { continue }
			if len(rest) < 2 || rest[1] == '=' { continue } // skip :=

			// Extract the type identifier after ':'
			type_part := strings.trim_space(rest[1:])
			end := 0
			for end < len(type_part) {
				c := type_part[end]
				if c == '=' || c == ',' || c == '{' || c == ')' || c == ';' { break }
				end += 1
			}
			type_name := strings.trim_space(type_part[:end])
			if len(type_name) > 0 && c202_is_valid_type_name(type_name) {
				return type_name
			}
		}
	}
	return ""
}

// c202_covered_cases returns the set of case label member names covered
// by the switch. Handles `.MemberName` and `TypeName.MemberName` patterns.
@(private = "file")
c202_covered_cases :: proc(switch_node: TSNode, lines: []string) -> map[string]bool {
	covered := make(map[string]bool)
	n := ts_node_child_count(switch_node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(switch_node, i)
		if ts_node_is_null(child) { continue }
		if string(ts_node_type(child)) != "switch_case" { continue }
		c202_collect_case_labels(child, lines, &covered)
	}
	return covered
}

@(private = "file")
c202_collect_case_labels :: proc(case_node: TSNode, lines: []string, covered: ^map[string]bool) {
	// A case_node may have multiple condition expressions for comma-separated cases:
	// case .A, .B: ...
	n := ts_node_child_count(case_node)
	for i: u32 = 0; i < n; i += 1 {
		child := ts_node_child(case_node, i)
		if ts_node_is_null(child) { continue }
		child_type := string(ts_node_type(child))
		switch child_type {
		case "identifier":
			// `case _:` wildcard or bare identifier
			name := naming_extract_text(child, lines)
			if name != "" { covered[name] = true }
		case "member_expression":
			// `.MemberName` or `TypeName.MemberName`
			// The last identifier in the member_expression is the member name.
			en := ts_node_child_count(child)
			for j := en; j > 0; j -= 1 {
				sub := ts_node_child(child, j-1)
				if ts_node_is_null(sub) { continue }
				sub_t := string(ts_node_type(sub))
				if sub_t == "field_identifier" || sub_t == "identifier" {
					name := naming_extract_text(sub, lines)
					if name != "" { covered[name] = true; break }
				}
			}
		}
	}
}


@(private = "file")
c202_is_valid_type_name :: proc(s: string) -> bool {
	if len(s) == 0 { return false }
	// Must start with uppercase or _ (Odin type naming convention)
	// Reject keywords and common non-type tokens
	if s == "int" || s == "string" || s == "bool" || s == "u8" || s == "u16" ||
	   s == "u32" || s == "u64" || s == "i8"  || s == "i16" || s == "i32" ||
	   s == "i64" || s == "f32" || s == "f64" || s == "byte" || s == "rune" {
		return false
	}
	return true
}
