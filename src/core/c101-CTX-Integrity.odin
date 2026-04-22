package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C101: Context allocator assigned without defer restore
// =============================================================================
//
// Detects procs that assign context.allocator (or context.temp_allocator)
// without a matching 'defer context.allocator = <saved>' restore, leaving
// the caller's allocator silently corrupted after the call returns.
//
// Correct pattern:
//   old := context.allocator
//   context.allocator = my_alloc
//   defer context.allocator = old   ← restore — no violation
//
// Flagged pattern:
//   context.allocator = my_alloc    ← C101: no defer restore
//
// ESCAPE HATCHES — the rule is silent when:
//   1. A 'defer context.allocator = ...' restore exists anywhere in the proc
//   2. 'context := context' appears (shadow copy pattern — modification is local)
//   3. An inline suppression comment is present
//   4. The line is a code comment
//
// SUPPRESSION:
//   context.allocator = my_alloc  // odin-lint:ignore C101
//
// =============================================================================

C101Rule :: proc() -> Rule {
    return Rule{
        id       = "C101",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c101_message,
        fix_hint = c101_fix_hint,
    }
}

c101_message  :: proc() -> string { return "context.allocator assigned without defer restore" }
c101_fix_hint :: proc() -> string {
    return "Save old value and add 'defer context.allocator = <saved>' after assignment"
}

// c101_run is the primary entry point.
// Walks the ASTNode tree, finds all proc bodies, and checks for missing
// defer restores on context.allocator / context.temp_allocator assignments.
c101_run :: proc(
    file_path:  string,
    root:       ^ASTNode,
    file_lines: []string,
) -> []Diagnostic {
    diags: [dynamic]Diagnostic
    c101_walk_node(file_path, root, file_lines, &diags)
    return diags[:]
}

// ---------------------------------------------------------------------------
// AST walker
// ---------------------------------------------------------------------------

@(private)
c101_walk_node :: proc(
    file_path:  string,
    node:       ^ASTNode,
    file_lines: []string,
    diags:      ^[dynamic]Diagnostic,
) {
    if node.node_type == "procedure_declaration" ||
       node.node_type == "procedure_literal" {
        if d, ok := c101_check_proc(file_path, node, file_lines); ok {
            append(diags, d)
        }
    }
    for &child in node.children {
        c101_walk_node(file_path, &child, file_lines, diags)
    }
}

// ---------------------------------------------------------------------------
// Per-proc check
// ---------------------------------------------------------------------------

@(private)
c101_check_proc :: proc(
    file_path:  string,
    proc_node:  ^ASTNode,
    file_lines: []string,
) -> (Diagnostic, bool) {
    start := proc_node.start_line - 1  // convert to 0-based index
    end   := min(proc_node.end_line, len(file_lines))

    if start < 0 || start >= len(file_lines) { return {}, false }

    // Collect nested procedure_literal line ranges so we don't double-count
    // their patterns against the outer proc.
    nested: [dynamic][2]int
    defer delete(nested)
    c101_collect_nested_procs(proc_node, &nested)

    has_assign      := false
    has_defer       := false
    has_ctx_shadow  := false
    assign_line     := 0
    assign_col      := 0
    assign_field    := ""

    for i in start..<end {
        line    := file_lines[i]
        trimmed := strings.trim_left(line, " \t")

        // Skip pure comment lines
        if strings.has_prefix(trimmed, "//") { continue }

        // Escape hatch: context shadow copy — assignments affect local copy only
        if strings.contains(line, "context := context") {
            has_ctx_shadow = true
            break
        }

        // Skip lines inside nested procedure literals
        line_num := i + 1  // 1-based
        in_nested := false
        for rng in nested {
            if line_num >= rng[0] && line_num <= rng[1] {
                in_nested = true
                break
            }
        }
        if in_nested { continue }

        // Strip inline comments before pattern matching
        code := line
        if ci := strings.index(line, "//"); ci >= 0 {
            code = line[:ci]
        }

        // Defer restore check (must come before assign check to avoid
        // the assign-check matching the RHS of a defer statement)
        if strings.contains(code, "defer context.allocator =") ||
           strings.contains(code, "defer context.temp_allocator =") {
            has_defer = true
            continue
        }

        // Non-defer assignment: context.allocator = ...
        if !has_assign {
            if strings.contains(code, "context.allocator =") {
                has_assign   = true
                assign_line  = line_num
                assign_col   = strings.index(code, "context.allocator =") + 1
                assign_field = "allocator"
            } else if strings.contains(code, "context.temp_allocator =") {
                has_assign   = true
                assign_line  = line_num
                assign_col   = strings.index(code, "context.temp_allocator =") + 1
                assign_field = "temp_allocator"
            }
        }
    }

    if !has_assign || has_defer || has_ctx_shadow { return {}, false }

    // Suppression
    suppressions := collect_suppressions(proc_node.start_line, proc_node.end_line, file_lines)
    if is_suppressed("C101", assign_line, suppressions) { return {}, false }

    return Diagnostic{
        file      = file_path,
        line      = assign_line,
        column    = assign_col,
        rule_id   = "C101",
        tier      = "correctness",
        message   = fmt.aprintf(
            "context.%s assigned without 'defer context.%s = ...' restore",
            assign_field, assign_field,
        ),
        has_fix   = true,
        fix       = fmt.aprintf(
            "Save the old value before the assignment and add 'defer context.%s = <saved>'",
            assign_field,
        ),
        diag_type = .VIOLATION,
    }, true
}

// c101_collect_nested_procs finds all procedure_literal nodes within the
// given node (stopping at nested procedure_literal boundaries) and records
// their line ranges for exclusion during the outer proc's line scan.
@(private)
c101_collect_nested_procs :: proc(node: ^ASTNode, ranges: ^[dynamic][2]int) {
    for &child in node.children {
        if child.node_type == "procedure_literal" {
            append(ranges, [2]int{child.start_line, child.end_line})
            // Do not recurse into this nested proc — the outer walker handles it
        } else {
            c101_collect_nested_procs(&child, ranges)
        }
    }
}
