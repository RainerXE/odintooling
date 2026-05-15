// c201-COR-UncheckedResult.odin — C201: unchecked error return value.
// SCM query finds bare call statements (not assigned) to procs that return an error
// or bool; uses the graph DB for project-local proc resolution beyond the stdlib list.
package core

import "core:fmt"

// =============================================================================
// C201: Unchecked error return — bare call to a proc that returns an error
// =============================================================================
// Detects call_expression statements whose return value is discarded and
// whose proc is known to return an error type. Uses TypeResolveContext:
//   1. stdlib curated list
//   2. graph DB (return_type field)
//   3. OLS stub (future)
//
// Parent-block filtering: a call_expression is "bare" (result discarded) only
// when its parent node is a block. Calls inside assignment_statement,
// return_statement, conditions, etc. are NOT flagged.
// Category: CORRECTNESS
// =============================================================================

c201_rule :: proc() -> Rule {
    return Rule{
        id       = "C201",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c201_message,
        fix_hint = c201_fix_hint,
    }
}

c201_message  :: proc() -> string { return "Error return value ignored — call result discarded" }
c201_fix_hint :: proc() -> string { return "Assign the result and handle the error, or use 'or_return'" }

c201_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
    type_ctx:   ^TypeResolveContext,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    suppressions := collect_suppressions(1, len(file_lines), file_lines)
    defer free_suppressions(suppressions)
    diagnostics  := make([dynamic]Diagnostic)

    seen := make(map[string]bool)
    defer delete(seen)

    for result in results {
        call_node, c_ok := result.captures["c201_call"]
        if !c_ok { continue }

        // Only flag bare calls: parent of call_expression must be a block.
        parent := ts_node_parent(call_node)
        if ts_node_is_null(parent) { continue }
        parent_type := string(ts_node_type(parent))
        // Qualified calls (os.open, net.dial_tcp, etc.) are parsed as:
        //   member_expression (parent=block)
        //     call_expression (parent=member_expression)  ← what we match
        // Plain calls (open, close, etc.) have call_expression directly in block.
        if parent_type == "member_expression" {
            gp := ts_node_parent(parent)
            if ts_node_is_null(gp) { continue }
            parent_type = string(ts_node_type(gp))
        }
        if parent_type != "block" { continue }

        // Extract the function name from the first child of the call_expression.
        // Structure: call_expression → [function_node, args...]
        // function_node is identifier (plain) or member_expression (qualified).
        fn_name := c201_extract_fn_name(call_node, file_lines)
        if len(fn_name) == 0 { continue }

        if !proc_returns_error(type_ctx, fn_name) { continue }

        pt  := ts_node_start_point(call_node)
        pos := Position{line = int(pt.row) + 1, col = int(pt.column) + 1}

        loc_key := fmt.tprintf("%d:%d", pos.line, pos.col)
        if seen[loc_key] { continue }
        seen[loc_key] = true

        if is_suppressed("C201", pos.line, suppressions) { continue }

        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = pos.line,
            column    = pos.col,
            rule_id   = "C201",
            tier      = "correctness",
            message   = fmt.aprintf("error return of '%s' is discarded", fn_name),
            has_fix   = true,
            fix       = "Assign the result and handle the error, or use 'or_return'",
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}

// c201_extract_fn_name returns the package-qualified function name for calls whose
// result is discarded, e.g. "net.send" for a bare net.send(...) call.
// Using the qualified form prevents false-positives when user code defines its own
// proc with the same short name (e.g. a custom send :: proc(...)).
@(private="file")
c201_extract_fn_name :: proc(call_node: TSNode, file_lines: []string) -> string {
    child_count := ts_node_child_count(call_node)
    if child_count == 0 { return "" }

    fn_node := ts_node_child(call_node, 0)
    if ts_node_is_null(fn_node) { return "" }

    fn_type := string(ts_node_type(fn_node))
    switch fn_type {
    case "identifier":
        fn_name := naming_extract_text(fn_node, file_lines)
        // In tree-sitter-odin, pkg.fn(args) is sometimes parsed as:
        //   member_expression → call_expression → identifier
        // If our call_node's parent is a member_expression, extract the package
        // identifier from it and return "pkg.fn" to match the qualified stdlib list.
        parent := ts_node_parent(call_node)
        if !ts_node_is_null(parent) && string(ts_node_type(parent)) == "member_expression" {
            pc := ts_node_child_count(parent)
            for i in 0..<int(pc) {
                child := ts_node_child(parent, u32(i))
                if ts_node_is_null(child) { continue }
                if string(ts_node_type(child)) == "identifier" {
                    pkg := naming_extract_text(child, file_lines)
                    if len(pkg) > 0 && pkg != fn_name {
                        return fmt.tprintf("%s.%s", pkg, fn_name)
                    }
                }
            }
        }
        return fn_name
    case "member_expression":
        // Standard grammar: call_expression with member_expression as function child.
        // Extract pkg (first identifier) and fn (field_identifier or second identifier).
        n   := ts_node_child_count(fn_node)
        pkg := ""
        fn  := ""
        for i in 0..<int(n) {
            child := ts_node_child(fn_node, u32(i))
            if ts_node_is_null(child) { continue }
            ct   := string(ts_node_type(child))
            text := naming_extract_text(child, file_lines)
            if len(text) == 0 { continue }
            switch ct {
            case "identifier":
                if pkg == "" { pkg = text } else { fn = text }
            case "field_identifier":
                fn = text
            }
        }
        if len(pkg) > 0 && len(fn) > 0 { return fmt.tprintf("%s.%s", pkg, fn) }
        if len(fn)  > 0               { return fn }
        return pkg
    }
    return ""
}
