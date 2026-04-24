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

C201Rule :: proc() -> Rule {
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

// c201_extract_fn_name returns the called function's short name (identifier only,
// not the package qualifier). Returns "" if not extractable.
@(private="file")
c201_extract_fn_name :: proc(call_node: TSNode, file_lines: []string) -> string {
    child_count := ts_node_child_count(call_node)
    if child_count == 0 { return "" }

    fn_node := ts_node_child(call_node, 0)
    if ts_node_is_null(fn_node) { return "" }

    fn_type := string(ts_node_type(fn_node))
    switch fn_type {
    case "identifier":
        return naming_extract_text(fn_node, file_lines)
    case "member_expression":
        // member_expression children: [pkg_ident, ".", fn_ident]
        // The last named child is the field identifier.
        n := ts_node_child_count(fn_node)
        for i := n; i > 0; i -= 1 {
            child := ts_node_child(fn_node, i - 1)
            if ts_node_is_null(child) { continue }
            ct := string(ts_node_type(child))
            if ct == "field_identifier" || ct == "identifier" {
                text := naming_extract_text(child, file_lines)
                if len(text) > 0 { return text }
            }
        }
    }
    return ""
}
