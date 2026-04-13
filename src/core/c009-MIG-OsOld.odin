package core

import "core:fmt"

// =============================================================================
// C009: Flag import "core:os/old" — deprecated legacy OS API
// =============================================================================
// core:os2 migration completed Q1 2026. The new API is core:os.
// core:os/old will be removed Q3 2026.
// Category: CORRECTNESS
// =============================================================================

C009Rule :: proc() -> Rule {
    return Rule{
        id       = "C009",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c009_message,
        fix_hint = c009_fix_hint,
    }
}

c009_message  :: proc() -> string { return "Import of deprecated core:os/old" }
c009_fix_hint :: proc() -> string { return "Replace 'core:os/old' with 'core:os' (the new API requires explicit allocator parameters)" }

c009_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        path_node, ok := result.captures["c009_path"]
        if !ok { continue }

        path_text := c009_extract_text(path_node, file_lines)
        if path_text != "core:os/old" { continue }

        pt := ts_node_start_point(path_node)
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = int(pt.row) + 1,
            column    = int(pt.column) + 1,
            rule_id   = "C009",
            tier      = "correctness",
            message   = fmt.aprintf("Import of deprecated 'core:os/old' — will be removed Q3 2026"),
            has_fix   = true,
            fix       = "Replace with 'core:os' (new unified OS API since Q1 2026)",
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}

// c009_extract_text extracts raw text from any node using start/end points (single line).
c009_extract_text :: proc(node: TSNode, lines: []string) -> string {
    start := ts_node_start_point(node)
    end   := ts_node_end_point(node)
    if int(start.row) != int(end.row)    { return "" }
    if int(start.row) >= len(lines)       { return "" }
    line := lines[int(start.row)]
    sc, ec := int(start.column), int(end.column)
    if sc < 0 || ec > len(line) || sc >= ec { return "" }
    return line[sc:ec]
}
