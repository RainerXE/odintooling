package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C003: Procedure names must use camelCase or snake_case (not PascalCase)
// =============================================================================
//
// In Odin, PascalCase is reserved for type names (structs, enums, unions).
// Procedure names should start with a lowercase letter.
//
// Violation:   InitParser :: proc() { ... }   ← starts uppercase
// OK:          init_parser :: proc() { ... }
// OK:          initParser  :: proc() { ... }
//
// Category: STYLE
// =============================================================================

C003Rule :: proc() -> Rule {
    return Rule{
        id       = "C003",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,  // called via naming_scm_run in main.odin
        message  = c003_message,
        fix_hint = c003_fix_hint,
    }
}

c003_message :: proc() -> string {
    return "Procedure name should start with lowercase (camelCase or snake_case, not PascalCase)"
}

c003_fix_hint :: proc() -> string {
    return "Rename: e.g. 'InitFoo' → 'initFoo' or 'init_foo'"
}

// ---------------------------------------------------------------------------
// Shared naming-rule SCM runner (C003 + C007 in one pass)
// ---------------------------------------------------------------------------

// naming_scm_run runs naming_rules.scm over the file and returns all C003 and
// C007 violations in a single pass.  Called once from main.odin.
naming_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        // C003: proc names must start lowercase
        if proc_node, ok := result.captures["proc_name"]; ok {
            name := naming_extract_text(proc_node, file_lines)
            if len(name) > 0 && name[0] >= 'A' && name[0] <= 'Z' {
                pt := ts_node_start_point(proc_node)
                append(&diagnostics, Diagnostic{
                    file      = file_path,
                    line      = int(pt.row) + 1,
                    column    = int(pt.column) + 1,
                    rule_id   = "C003",
                    tier      = "style",
                    message   = fmt.aprintf(
                        "Procedure '%s' starts with uppercase — use camelCase or snake_case",
                        name,
                    ),
                    has_fix   = true,
                    fix       = fmt.aprintf("Rename '%s' to '%c%s'",
                        name, name[0] + 32, name[1:]),
                    diag_type = .VIOLATION,
                })
            }
        }

        // C007: struct/enum type names must start uppercase
        struct_node, has_struct := result.captures["struct_name"]
        enum_node,   has_enum   := result.captures["enum_name"]

        if has_struct || has_enum {
            type_node := struct_node if has_struct else enum_node
            name := naming_extract_text(type_node, file_lines)
            if len(name) > 0 && name[0] >= 'a' && name[0] <= 'z' {
                pt := ts_node_start_point(type_node)
                append(&diagnostics, Diagnostic{
                    file      = file_path,
                    line      = int(pt.row) + 1,
                    column    = int(pt.column) + 1,
                    rule_id   = "C007",
                    tier      = "style",
                    message   = fmt.aprintf(
                        "Type '%s' starts with lowercase — use PascalCase for type names",
                        name,
                    ),
                    has_fix   = true,
                    fix       = fmt.aprintf("Rename '%s' to '%c%s'",
                        name, name[0] - 32, name[1:]),
                    diag_type = .VIOLATION,
                })
            }
        }

        // C016: local variable names must be snake_case
        if d, ok := c016_scm_run(file_path, result.captures, file_lines); ok {
            append(&diagnostics, d)
        }

        // C017: package-level variable names must be camelCase (opt-in)
        if d, ok := c017_scm_run(file_path, result.captures, file_lines); ok {
            append(&diagnostics, d)
        }

        // C018: proc naming must reflect @(private) visibility (opt-in)
        if d, ok := c018_scm_run(file_path, result.captures, file_lines); ok {
            append(&diagnostics, d)
        }
    }

    return diagnostics[:]
}

// naming_extract_text extracts identifier text from a TSNode using file_lines.
naming_extract_text :: proc(node: TSNode, lines: []string) -> string {
    type_str := string(ts_node_type(node))
    if type_str != "identifier" { return "" }

    pt      := ts_node_start_point(node)
    line_idx := int(pt.row)
    if line_idx < 0 || line_idx >= len(lines) { return "" }

    line := lines[line_idx]
    col  := int(pt.column)
    if col < 0 || col >= len(line) { return "" }

    rest := line[col:]
    end  := 0
    for end < len(rest) {
        c := rest[end]
        if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') {
            end += 1
        } else {
            break
        }
    }
    return rest[:end]
}
