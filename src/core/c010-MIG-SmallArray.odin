package core

import "core:fmt"

// =============================================================================
// C010: Flag Small_Array — superseded by [dynamic; N]T (dev-2026-04)
// =============================================================================
// core:container/small_array.Small_Array(N, T) is superseded by the built-in
// fixed-capacity dynamic array syntax [dynamic; N]T.
// Category: CORRECTNESS
// =============================================================================

C010Rule :: proc() -> Rule {
    return Rule{
        id       = "C010",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c010_message,
        fix_hint = c010_fix_hint,
    }
}

c010_message  :: proc() -> string { return "Small_Array superseded by [dynamic; N]T" }
c010_fix_hint :: proc() -> string { return "Replace Small_Array(N, T) with [dynamic; N]T" }

// c010_leading_ident extracts the leading identifier from a node's source text.
// Used for polymorphic_type nodes where the type name precedes '('.
// e.g. "Small_Array(8, int)" → "Small_Array"
c010_leading_ident :: proc(node: TSNode, lines: []string) -> string {
    pt := ts_node_start_point(node)
    if int(pt.row) >= len(lines) { return "" }
    line := lines[int(pt.row)]
    col  := int(pt.column)
    if col >= len(line) { return "" }
    end := col
    for end < len(line) {
        c := line[end]
        if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
            end += 1
        } else {
            break
        }
    }
    return line[col:end]
}

c010_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        // C010-a: polymorphic_type (type annotation position: arr: Small_Array(8, int))
        // Captures the whole node; extract the leading identifier from source text.
        if poly_node, ok := result.captures["c010_poly"]; ok {
            name := c010_leading_ident(poly_node, file_lines)
            if name != "Small_Array" { continue }
            pt := ts_node_start_point(poly_node)
            append(&diagnostics, Diagnostic{
                file      = file_path,
                line      = int(pt.row) + 1,
                column    = int(pt.column) + 1,
                rule_id   = "C010",
                tier      = "correctness",
                message   = fmt.aprintf("'Small_Array' is superseded by the built-in fixed-capacity array '[dynamic; N]T'"),
                has_fix   = true,
                fix       = "Replace 'Small_Array(N, T)' with '[dynamic; N]T' (e.g. 'Small_Array(8, int)' → '[dynamic; 8]int')",
                diag_type = .VIOLATION,
            })
            continue
        }

        // C010-b: call_expression (expression position: x := Small_Array(8, int){})
        fn_node, ok := result.captures["c010_fn"]
        if !ok { continue }

        fn_name := naming_extract_text(fn_node, file_lines)
        if fn_name != "Small_Array" { continue }

        pt := ts_node_start_point(fn_node)
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = int(pt.row) + 1,
            column    = int(pt.column) + 1,
            rule_id   = "C010",
            tier      = "correctness",
            message   = fmt.aprintf("'Small_Array' is superseded by the built-in fixed-capacity array '[dynamic; N]T'"),
            has_fix   = true,
            fix       = "Replace 'Small_Array(N, T)' with '[dynamic; N]T' (e.g. 'Small_Array(8, int)' → '[dynamic; 8]int')",
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}
