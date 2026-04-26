// c029-c033-STD-Safety.odin — C029/C033: stdlib allocation safety (stdlib_safety domain).
// C029 detects strings.split/clone/join/fmt.aprintf/os.read_entire_file without defer delete;
// C033 detects strings.builder_make() without defer strings.builder_destroy.
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C029 — stdlib Allocating Proc Result Not Freed
// C033 — strings.Builder Not Destroyed
// =============================================================================
// Enabled via [domains] stdlib_safety = true in olt.toml.
//
// C029: Extends C001 to known stdlib allocating procs:
//   strings.split / clone / join / concatenate / repeat / to_lower / to_upper
//   fmt.aprintf / aprintfln
//   os.read_entire_file / read_entire_file_from_path
// Each returns a heap-allocated value that must be freed with defer delete().
//
// C033: strings.builder_make() must be paired with defer strings.builder_destroy().
//
// Escape hatches (same as C001):
//   1. defer delete(var)          — explicit cleanup registered
//   2. return var                 — ownership transferred to caller
//   3. custom allocator argument  — caller controls lifetime
//   4. context.allocator assigned in block (arena pattern)
//   5. proc name ends in _init    — module-lifetime allocation
//   6. explicit (non-defer) delete/free anywhere in block
//   7. // olt:ignore C029 / C033 inline suppression
// =============================================================================

// Stdlib procs whose results require defer delete(). The trailing "(" is
// included so "strings.clone_from" doesn't match "strings.clone(".
C029_ALLOC_PROCS :: [?]string{
	"strings.split(",
	"strings.split_lines(",
	"strings.split_by_byte(",
	"strings.split_after(",
	"strings.split_after_lines(",
	"strings.clone(",
	"strings.clone_from_bytes(",
	"strings.join(",
	"strings.concatenate(",
	"strings.repeat(",
	"strings.to_lower(",
	"strings.to_upper(",
	"fmt.aprintf(",
	"fmt.aprintfln(",
	"os.read_entire_file(",
	"os.read_entire_file_from_path(",
}

// =============================================================================
// C029
// =============================================================================

c029_run :: proc(file_path: string, root: ^ASTNode, file_lines: []string) -> []Diagnostic {
	if should_exclude_file(file_path) { return {} }
	all := make([dynamic]Diagnostic)
	c029_walk(file_path, root, file_lines, &all)
	return all[:]
}

@(private = "file")
c029_walk :: proc(file_path: string, node: ^ASTNode, file_lines: []string, out: ^[dynamic]Diagnostic) {
	if node.node_type == "block" {
		for d in c029_check_block(node, file_path, file_lines) {
			append(out, d)
		}
	}
	for &child in node.children {
		c029_walk(file_path, &child, file_lines, out)
	}
}

@(private = "file")
c029_check_block :: proc(block: ^ASTNode, file_path: string, file_lines: []string) -> []Diagnostic {
	proc_name := get_enclosing_proc_name(block, file_lines)
	if strings.has_suffix(proc_name, "_init") ||
	   strings.has_prefix(proc_name, "init_") ||
	   proc_name == "init" {
		return {}
	}

	allocations := make([dynamic]AllocationInfo)
	defer delete(allocations)
	freed    := make(map[string]bool)
	defer delete(freed)
	returned := make(map[string]bool)
	defer delete(returned)
	has_arena := false

	for &child in block.children {
		if c029_is_stdlib_alloc(&child, file_lines) {
			var_name := c029_extract_alloc_var(&child, file_lines)
			if var_name == "" { continue }
			if has_manual_cleanup(var_name, block) { continue }
			append(&allocations, AllocationInfo{
				var_name = var_name,
				line     = child.start_line,
				col      = child.start_column,
			})
		}
		if is_defer_free(&child) {
			if v := extract_freed_var_name(&child); v != "" {
				freed[v] = true
			}
		}
		// Use a conservative arena check: only fire when context.allocator
		// is being ASSIGNED (not merely passed as an argument).
		if c029_block_uses_arena(&child, file_lines) { has_arena = true }
		if is_return_statement(&child) {
			extract_returned_vars(&child, &returned)
		}
	}

	if has_arena { return {} }

	suppressions := collect_suppressions(block.start_line, block.end_line, file_lines)
	defer free_suppressions(suppressions)

	diags := make([dynamic]Diagnostic)
	for alloc in allocations {
		if is_suppressed("C029", alloc.line, suppressions) { continue }
		if alloc.var_name in returned { continue }
		if alloc.var_name in freed    { continue }

		msg := fmt.aprintf(
			"stdlib allocation '%s' has no matching 'defer delete(%s)' — leaks when proc returns",
			alloc.var_name, alloc.var_name)
		append(&diags, Diagnostic{
			file      = file_path,
			line      = alloc.line,
			column    = alloc.col,
			rule_id   = "C029",
			tier      = "correctness",
			message   = msg,
			fix       = fmt.aprintf("Add 'defer delete(%s)' immediately after the allocation", alloc.var_name),
			has_fix   = true,
			diag_type = .VIOLATION,
		})
	}
	return diags[:]
}

// c029_is_stdlib_alloc returns true when node is an assignment_statement
// whose source line contains a known stdlib allocating proc call on the RHS.
// Uses text-based matching because tree-sitter-odin represents pkg.func(...)
// as a member_expression, not a call_expression with a selector child.
@(private = "file")
c029_is_stdlib_alloc :: proc(node: ^ASTNode, file_lines: []string) -> bool {
	if node.node_type != "assignment_statement" { return false }
	if node.start_line < 1 || node.start_line > len(file_lines) { return false }
	line := file_lines[node.start_line - 1]

	// Must be a := declaration.
	eq_pos := strings.index(line, ":=")
	if eq_pos < 0 { return false }

	// LHS must not contain a dot — skip field assignments: thing.field := alloc(...)
	lhs := strings.trim(line[:eq_pos], " \t")
	if strings.contains(lhs, ".") { return false }

	// Examine the RHS (strip inline comments).
	rhs := line[eq_pos + 2:]
	if ci := strings.index(rhs, "//"); ci >= 0 { rhs = rhs[:ci] }

	// Skip when a non-default allocator is explicitly passed.
	// Any occurrence of "allocator" that is NOT "context.allocator" means the
	// caller controls the lifetime explicitly (arena, temp, custom).
	if c029_has_custom_allocator_arg(rhs) { return false }

	for pat in C029_ALLOC_PROCS {
		if strings.contains(rhs, pat) { return true }
	}
	return false
}

// c029_extract_alloc_var extracts the first LHS identifier from a := line.
@(private = "file")
c029_extract_alloc_var :: proc(node: ^ASTNode, file_lines: []string) -> string {
	if node.start_line < 1 || node.start_line > len(file_lines) { return "" }
	line := file_lines[node.start_line - 1]
	eq_pos := strings.index(line, ":=")
	if eq_pos < 0 { return "" }
	lhs := strings.trim(line[:eq_pos], " \t")
	// For multi-return "parts, ok" take only the first identifier.
	if comma_pos := strings.index(lhs, ","); comma_pos >= 0 {
		lhs = strings.trim(lhs[:comma_pos], " \t")
	}
	end := 0
	for end < len(lhs) && is_ident_byte(lhs[end]) { end += 1 }
	if end == 0 { return "" }
	return lhs[:end]
}

// =============================================================================
// C033 — strings.Builder Not Destroyed
// =============================================================================

c033_run :: proc(file_path: string, root: ^ASTNode, file_lines: []string) -> []Diagnostic {
	if should_exclude_file(file_path) { return {} }
	all := make([dynamic]Diagnostic)
	c033_walk(file_path, root, file_lines, &all)
	return all[:]
}

@(private = "file")
c033_walk :: proc(file_path: string, node: ^ASTNode, file_lines: []string, out: ^[dynamic]Diagnostic) {
	if node.node_type == "block" {
		for d in c033_check_block(node, file_path, file_lines) {
			append(out, d)
		}
	}
	for &child in node.children {
		c033_walk(file_path, &child, file_lines, out)
	}
}

@(private = "file")
c033_check_block :: proc(block: ^ASTNode, file_path: string, file_lines: []string) -> []Diagnostic {
	proc_name := get_enclosing_proc_name(block, file_lines)
	if strings.has_suffix(proc_name, "_init") ||
	   strings.has_prefix(proc_name, "init_") ||
	   proc_name == "init" {
		return {}
	}

	allocations := make([dynamic]AllocationInfo)
	defer delete(allocations)
	destroyed := make(map[string]bool)
	defer delete(destroyed)
	returned  := make(map[string]bool)
	defer delete(returned)
	has_arena := false

	for &child in block.children {
		if c033_is_builder_alloc(&child, file_lines) {
			var_name := c033_extract_builder_var(&child, file_lines)
			if var_name == "" { continue }
			if c033_has_manual_destroy(var_name, block, file_lines) { continue }
			append(&allocations, AllocationInfo{
				var_name = var_name,
				line     = child.start_line,
				col      = child.start_column,
			})
		}
		if c033_is_defer_destroy(&child, file_lines) {
			if v := c033_extract_destroyed_var(&child, file_lines); v != "" {
				destroyed[v] = true
			}
		}
		// Also accept defer delete(sb) as an alternative cleanup
		if is_defer_free(&child) {
			if v := extract_freed_var_name(&child); v != "" {
				destroyed[v] = true
			}
		}
		if c029_block_uses_arena(&child, file_lines) { has_arena = true }
		// Only skip if the builder itself is directly returned (not a view into it).
		// `return sb` transfers ownership; `return strings.to_string(sb)` does NOT.
		if is_return_statement(&child) {
			c033_collect_direct_returns(&child, &returned)
		}
	}

	if has_arena { return {} }

	suppressions := collect_suppressions(block.start_line, block.end_line, file_lines)
	defer free_suppressions(suppressions)

	diags := make([dynamic]Diagnostic)
	for alloc in allocations {
		if is_suppressed("C033", alloc.line, suppressions) { continue }
		if alloc.var_name in returned  { continue }
		if alloc.var_name in destroyed { continue }

		msg := fmt.aprintf(
			"'%s' is a strings.Builder without 'defer strings.builder_destroy(&%s)' — leaks its internal buffer",
			alloc.var_name, alloc.var_name)
		append(&diags, Diagnostic{
			file      = file_path,
			line      = alloc.line,
			column    = alloc.col,
			rule_id   = "C033",
			tier      = "correctness",
			message   = msg,
			fix       = fmt.aprintf("Add 'defer strings.builder_destroy(&%s)' immediately after the allocation", alloc.var_name),
			has_fix   = true,
			diag_type = .VIOLATION,
		})
	}
	return diags[:]
}

@(private = "file")
c033_is_builder_alloc :: proc(node: ^ASTNode, file_lines: []string) -> bool {
	if node.node_type != "assignment_statement" { return false }
	if node.start_line < 1 || node.start_line > len(file_lines) { return false }
	line := file_lines[node.start_line - 1]
	eq_pos := strings.index(line, ":=")
	if eq_pos < 0 { return false }
	lhs := strings.trim(line[:eq_pos], " \t")
	if strings.contains(lhs, ".") { return false }
	rhs := line[eq_pos + 2:]
	if ci := strings.index(rhs, "//"); ci >= 0 { rhs = rhs[:ci] }
	if !strings.contains(rhs, "strings.builder_make(") { return false }
	// Skip when a non-default allocator is passed — caller controls lifetime.
	if c029_has_custom_allocator_arg(rhs) { return false }
	return true
}

@(private = "file")
c033_extract_builder_var :: proc(node: ^ASTNode, file_lines: []string) -> string {
	if node.start_line < 1 || node.start_line > len(file_lines) { return "" }
	line := file_lines[node.start_line - 1]
	eq_pos := strings.index(line, ":=")
	if eq_pos < 0 { return "" }
	lhs := strings.trim(line[:eq_pos], " \t")
	if comma_pos := strings.index(lhs, ","); comma_pos >= 0 {
		lhs = strings.trim(lhs[:comma_pos], " \t")
	}
	end := 0
	for end < len(lhs) && is_ident_byte(lhs[end]) { end += 1 }
	if end == 0 { return "" }
	return lhs[:end]
}

@(private = "file")
c033_is_defer_destroy :: proc(node: ^ASTNode, file_lines: []string) -> bool {
	if node.node_type != "defer_statement" { return false }
	if node.start_line < 1 || node.start_line > len(file_lines) { return false }
	line := file_lines[node.start_line - 1]
	return strings.contains(line, "strings.builder_destroy(")
}

@(private = "file")
c033_extract_destroyed_var :: proc(node: ^ASTNode, file_lines: []string) -> string {
	if node.start_line < 1 || node.start_line > len(file_lines) { return "" }
	line := file_lines[node.start_line - 1]
	pat  := "strings.builder_destroy("
	pos  := strings.index(line, pat)
	if pos < 0 { return "" }
	after := line[pos + len(pat):]
	if strings.has_prefix(after, "&") { after = after[1:] }
	end := 0
	for end < len(after) && is_ident_byte(after[end]) { end += 1 }
	if end == 0 { return "" }
	return after[:end]
}

// c033_has_manual_destroy checks if there is a non-defer builder_destroy in the block.
@(private = "file")
c033_has_manual_destroy :: proc(var_name: string, block: ^ASTNode, file_lines: []string) -> bool {
	for &child in block.children {
		if child.start_line < 1 || child.start_line > len(file_lines) { continue }
		line := file_lines[child.start_line - 1]
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }
		if strings.contains(code, "strings.builder_destroy(") &&
		   strings.contains(code, var_name) {
			return true
		}
	}
	return false
}

// c033_collect_direct_returns adds identifiers that appear as DIRECT return values
// (not nested inside function call arguments) to result.
// `return sb` → adds "sb".  `return strings.to_string(sb)` → adds nothing.
@(private = "file")
c033_collect_direct_returns :: proc(ret_node: ^ASTNode, result: ^map[string]bool) {
	for &child in ret_node.children {
		switch child.node_type {
		case "identifier":
			if child.text != "" { result[child.text] = true }
		case "expression_list":
			for &expr in child.children {
				if expr.node_type == "identifier" && expr.text != "" {
					result[expr.text] = true
				}
			}
		// Deliberately NOT recursing into call_expression or member_expression.
		}
	}
}

// c029_has_custom_allocator_arg returns true when the RHS of an assignment
// contains an allocator argument that is NOT "context.allocator" (the default).
// Custom allocators (temp_allocator, arena_allocator, bare `allocator` variable)
// mean the caller controls the lifetime — no defer delete needed.
@(private = "file")
c029_has_custom_allocator_arg :: proc(rhs: string) -> bool {
	check := rhs
	for {
		idx := strings.index(check, "allocator")
		if idx < 0 { break }
		// If this is "context.allocator", it's the default — skip over it.
		if idx >= len("context.") && check[idx-len("context."):idx] == "context." {
			check = check[idx + len("allocator"):]
			continue
		}
		return true  // Found an allocator that is NOT context.allocator
	}
	return false
}

// c029_block_uses_arena is a conservative check: returns true only when
// context.allocator is being REASSIGNED in this block (arena pattern).
// Unlike changes_context_allocator, this does NOT fire when context.allocator
// appears as a function call argument.
@(private = "file")
c029_block_uses_arena :: proc(node: ^ASTNode, file_lines: []string) -> bool {
	if node.node_type != "assignment_statement" { return false }
	if node.start_line < 1 || node.start_line > len(file_lines) { return false }
	line := file_lines[node.start_line - 1]
	// Strip inline comments before checking.
	code := line
	if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }
	// Look for assignment TO context.allocator (not usage as argument).
	// Only fires for "context.allocator =" (i.e., it's on the LHS).
	eq_pos := strings.index(code, "context.allocator")
	if eq_pos < 0 { return false }
	after := strings.trim(code[eq_pos + len("context.allocator"):], " \t")
	return strings.has_prefix(after, "=") && !strings.has_prefix(after, "==")
}
