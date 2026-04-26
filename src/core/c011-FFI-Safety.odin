// c011-FFI-Safety.odin — C011: FFI resource leak detection.
// Detects tree-sitter ts_*_new() allocations without a matching defer ts_*_delete().
// Enabled only when the ffi domain is active (projects with a ffi/ directory).
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C011: FFI memory safety — ts_*_new without matching defer ts_*_delete
// =============================================================================
// Pattern 2 (P2): C resource handle allocated without paired cleanup.
// Patterns P1 (C string cloning) and P3 (error param ignored) require
// cross-statement dataflow analysis — deferred to M6.
// Category: CORRECTNESS
// =============================================================================

c011_rule :: proc() -> Rule {
    return Rule{
        id       = "C011",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c011_message,
        fix_hint = c011_fix_hint,
    }
}

c011_message  :: proc() -> string { return "FFI C resource allocated without paired cleanup" }
c011_fix_hint :: proc() -> string { return "Add 'defer ts_*_delete(handle)' immediately after allocation" }

c011_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    // new_to_delete maps ts_*_new function names to their corresponding delete.
    new_to_delete := make(map[string]string)
    defer delete(new_to_delete)
    new_to_delete["ts_query_new"]        = "ts_query_delete"
    new_to_delete["ts_parser_new"]       = "ts_parser_delete"
    new_to_delete["ts_query_cursor_new"] = "ts_query_cursor_delete"

    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    // alloc_sites: "block_start:var_name" → Position of the allocation
    alloc_sites   := make(map[string]Position)
    alloc_fn      := make(map[string]string)   // same key → new_fn name
    // free_sites:  "block_start:var_name" → true (has matching defer delete)
    free_sites    := make(map[string]bool)
    // returned_vars: var_name → true (returned from proc; ownership transferred)
    returned_vars := make(map[string]bool)
    defer delete(alloc_sites)
    defer delete(alloc_fn)
    defer delete(free_sites)
    defer delete(returned_vars)

    for result in results {
        // C011-P2 allocation side
        if handle_node, ok1 := result.captures["c011_handle"]; ok1 {
            if new_fn_node, ok2 := result.captures["c011_new_fn"]; ok2 {
                fn_name  := naming_extract_text(new_fn_node, file_lines)
                _, is_ts_new := new_to_delete[fn_name]
                if !is_ts_new { continue }

                var_name := naming_extract_text(handle_node, file_lines)
                if len(var_name) == 0 { continue }

                block_start := c002_scm_block_scope(handle_node)
                key         := fmt.tprintf("%d:%s", block_start, var_name)
                pt          := ts_node_start_point(handle_node)
                alloc_sites[key] = Position{line = int(pt.row) + 1, col = int(pt.column) + 1}
                alloc_fn[key]    = fn_name
            }
        }

        // C011-P2 cleanup side
        if del_fn_node, ok1 := result.captures["c011_del_fn"]; ok1 {
            if del_arg_node, ok2 := result.captures["c011_del_arg"]; ok2 {
                del_fn_name  := naming_extract_text(del_fn_node, file_lines)
                del_arg_name := naming_extract_text(del_arg_node, file_lines)
                if len(del_arg_name) == 0 { continue }

                block_start := c002_scm_block_scope(del_arg_node)
                key         := fmt.tprintf("%d:%s", block_start, del_arg_name)

                is_ts_delete := strings.has_prefix(del_fn_name, "ts_") &&
                                strings.has_suffix(del_fn_name, "_delete")
                if is_ts_delete {
                    free_sites[key] = true
                }
            }
        }

        // Escape hatch: returned variables transfer ownership to the caller
        if ret_node, ok := result.captures["c011_return_var"]; ok {
            var_name := naming_extract_text(ret_node, file_lines)
            if len(var_name) > 0 {
                returned_vars[var_name] = true
            }
        }
    }

    suppressions := collect_suppressions(1, len(file_lines), file_lines)
    defer delete(suppressions)
    diagnostics := make([dynamic]Diagnostic)

    for key, pos in alloc_sites {
        if free_sites[key] { continue }
        fn_name := alloc_fn[key]
        expected_delete := new_to_delete[fn_name]
        colon_idx := strings.index(key, ":")
        var_name  := key[colon_idx+1:] if colon_idx >= 0 else key
        // Escape hatch: handle is returned → ownership transferred, no cleanup needed here
        if returned_vars[var_name] { continue }
        if is_suppressed("C011", pos.line, suppressions) { continue }
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = pos.line,
            column    = pos.col,
            rule_id   = "C011",
            tier      = "correctness",
            message   = fmt.aprintf(
                "C resource '%s' allocated via %s() without matching defer %s(%s)",
                var_name, fn_name, expected_delete, var_name,
            ),
            has_fix   = true,
            fix       = fmt.aprintf("Add 'defer %s(%s)' immediately after allocation", expected_delete, var_name),
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}
