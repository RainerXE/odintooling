package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C012: Semantic ownership naming conventions
// =============================================================================
//
// Suggests variable name suffixes that encode memory ownership semantics:
//
//   _owned     — variable holds heap-allocated memory caller must free
//   _view      — variable is a slice/pointer into memory owned elsewhere
//   _borrowed  — alias for _view (either suffix suppresses the hint)
//   alloc/allocator — variable holds an allocator value
//
// Fires INFO, never VIOLATION. Disabled by default (pass --enable-c012).
//
// Phase 1 (M3.3): Syntactic sub-rules S1–S3 via SCM query engine.
// Phase 2 (M6):   Type-gated rules S4+ requiring OLS type resolution.
//
// SCM file: ffi/tree_sitter/queries/c012_rules.scm
//
// Category: STYLE (opt-in semantic hint)
// =============================================================================

C012Rule :: proc() -> Rule {
    return Rule{
        id       = "C012",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c012_message,
        fix_hint = c012_fix_hint,
    }
}

c012_message  :: proc() -> string { return "Semantic ownership naming hint" }
c012_fix_hint :: proc() -> string { return "Add ownership suffix: _owned, _view, _borrowed, or include 'alloc' in allocator variable names" }

// c012_scm_run runs the c012_rules.scm query and emits INFO diagnostics.
// Called from main.odin only when --enable-c012 is present.
c012_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {

        // C012-S1: make/new allocation without _owned suffix
        if alloc_var_node, ok1 := result.captures["c012_alloc_var"]; ok1 {
            if alloc_fn_node, ok2 := result.captures["c012_alloc_fn"]; ok2 {
                var_name := naming_extract_text(alloc_var_node, file_lines)
                fn_name  := naming_extract_text(alloc_fn_node, file_lines)
                if len(var_name) > 0 &&
                   (fn_name == "make" || fn_name == "new") &&
                   !strings.has_suffix(var_name, "_owned") {
                    pt := ts_node_start_point(alloc_var_node)
                    append(&diagnostics, Diagnostic{
                        file      = file_path,
                        line      = int(pt.row) + 1,
                        column    = int(pt.column) + 1,
                        rule_id   = "C012",
                        tier      = "style",
                        message   = fmt.aprintf(
                            "Variable '%s' holds allocated memory — consider suffix '_owned' to signal caller must free",
                            var_name,
                        ),
                        has_fix   = true,
                        fix       = fmt.aprintf("Rename '%s' to '%s_owned'", var_name, var_name),
                        diag_type = .INFO,
                    })
                }
            }
        }

        // C012-S2: slice expression without _view or _borrowed
        if slice_var_node, ok := result.captures["c012_slice_var"]; ok {
            var_name := naming_extract_text(slice_var_node, file_lines)
            if len(var_name) > 0 &&
               !strings.contains(var_name, "_view") &&
               !strings.contains(var_name, "_borrowed") {
                pt := ts_node_start_point(slice_var_node)
                append(&diagnostics, Diagnostic{
                    file      = file_path,
                    line      = int(pt.row) + 1,
                    column    = int(pt.column) + 1,
                    rule_id   = "C012",
                    tier      = "style",
                    message   = fmt.aprintf(
                        "Variable '%s' is a slice view — consider suffix '_view' or '_borrowed' to signal no ownership",
                        var_name,
                    ),
                    has_fix   = true,
                    fix       = fmt.aprintf("Rename '%s' to '%s_view'", var_name, var_name),
                    diag_type = .INFO,
                })
            }
        }

        // C012-S3: package-qualified allocator call without alloc/allocator in name
        if qalloc_var_node, ok1 := result.captures["c012_qalloc_var"]; ok1 {
            if qalloc_fn_node, ok2 := result.captures["c012_qalloc_fn"]; ok2 {
                var_name := naming_extract_text(qalloc_var_node, file_lines)
                fn_name  := naming_extract_text(qalloc_fn_node, file_lines)
                is_known_alloc := fn_name == "tracking_allocator" ||
                                  fn_name == "arena_allocator"    ||
                                  fn_name == "temp_allocator"
                has_alloc_hint := strings.contains(var_name, "alloc") ||
                                  strings.contains(var_name, "allocator")
                if is_known_alloc && !has_alloc_hint && len(var_name) > 0 {
                    pt := ts_node_start_point(qalloc_var_node)
                    append(&diagnostics, Diagnostic{
                        file      = file_path,
                        line      = int(pt.row) + 1,
                        column    = int(pt.column) + 1,
                        rule_id   = "C012",
                        tier      = "style",
                        message   = fmt.aprintf(
                            "Variable '%s' holds an allocator — consider including 'alloc' or 'allocator' in the name",
                            var_name,
                        ),
                        has_fix   = true,
                        fix       = fmt.aprintf("Rename '%s' to '%s_alloc'", var_name, var_name),
                        diag_type = .INFO,
                    })
                }
            }
        }
    }

    return diagnostics[:]
}
