package core

import "core:fmt"
import sq "../../vendor/odin-sqlite3"
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
// T1    (M7.1):   mem.Allocator/runtime.Allocator → needs alloc/allocator in name.
// T2    (M12):    mem.Arena/virtual.Arena → needs 'arena' in name.
// T3    (M7.1):   allocator-role proc return → result needs _owned suffix.
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

        // C012-T1: explicitly typed mem.Allocator / runtime.Allocator variable
        // C012-T2: explicitly typed mem.Arena / virtual.Arena variable
        if t1_node, ok := result.captures["c012_t1_var"]; ok {
            var_name := naming_extract_text(t1_node, file_lines)
            if len(var_name) > 0 {
                pt  := ts_node_start_point(t1_node)
                row := int(pt.row)
                if row < len(file_lines) {
                    src := file_lines[row]

                    // T1: mem.Allocator / runtime.Allocator → needs alloc/allocator
                    is_alloc_type := strings.contains(src, "mem.Allocator") ||
                                     strings.contains(src, "runtime.Allocator")
                    has_alloc_hint := strings.contains(var_name, "alloc") ||
                                      strings.contains(var_name, "allocator")
                    if is_alloc_type && !has_alloc_hint {
                        append(&diagnostics, Diagnostic{
                            file      = file_path,
                            line      = row + 1,
                            column    = int(pt.column) + 1,
                            rule_id   = "C012",
                            tier      = "style",
                            message   = fmt.aprintf(
                                "Variable '%s' is typed mem.Allocator — include 'alloc' or 'allocator' in the name to signal its role",
                                var_name,
                            ),
                            has_fix   = true,
                            fix       = fmt.aprintf("Rename '%s' to '%s_alloc'", var_name, var_name),
                            diag_type = .INFO,
                        })
                    }

                    // T2: mem.Arena / virtual.Arena → needs 'arena' in name
                    is_arena_type := strings.contains(src, "mem.Arena") ||
                                     strings.contains(src, "virtual.Arena")
                    has_arena_hint := strings.contains(var_name, "arena")
                    if is_arena_type && !has_arena_hint {
                        append(&diagnostics, Diagnostic{
                            file      = file_path,
                            line      = row + 1,
                            column    = int(pt.column) + 1,
                            rule_id   = "C012",
                            tier      = "style",
                            message   = fmt.aprintf(
                                "Variable '%s' is typed mem.Arena — include 'arena' in the name to signal its role",
                                var_name,
                            ),
                            has_fix   = true,
                            fix       = fmt.aprintf("Rename '%s' to '%s_arena'", var_name, var_name),
                            diag_type = .INFO,
                        })
                    }
                }
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

// =============================================================================
// C012-T3: callee is graph-known allocator-role proc, LHS lacks _owned
// =============================================================================
//
// Fires when:
//   result := allocator_factory_proc()
// where `allocator_factory_proc` has memory_role='allocator' in the code graph
// and `result` does not contain '_owned'.
//
// Requires the code graph to have been built (--export-symbols).
// Called from main.odin only when --enable-c012 and graph DB is present.
//
// db_path: path to the graph SQLite DB (GRAPH_DB_PATH by default).
// =============================================================================
c012_t3_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
    db_path:    string,
) -> []Diagnostic {
    db, db_ok := graph_open(db_path)
    if !db_ok { return nil }
    defer graph_close(db)

    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        // Check both direct calls (@c012_alloc_fn) and qualified calls (@c012_qalloc_fn).
        callee_name := ""
        var_node:    TSNode
        var_ok := false

        if fn_node, ok1 := result.captures["c012_alloc_fn"]; ok1 {
            if v, ok2 := result.captures["c012_alloc_var"]; ok2 {
                callee_name = naming_extract_text(fn_node, file_lines)
                var_node    = v
                var_ok      = true
            }
        } else if fn_node, ok1 := result.captures["c012_qalloc_fn"]; ok1 {
            if v, ok2 := result.captures["c012_qalloc_var"]; ok2 {
                callee_name = naming_extract_text(fn_node, file_lines)
                var_node    = v
                var_ok      = true
            }
        }

        if !var_ok || callee_name == "" { continue }

        // Skip builtins — they're handled by S1 already.
        if callee_name == "make" || callee_name == "new" { continue }

        // Look up the callee in the graph.
        role := _c012_t3_get_role(db, callee_name)
        if role != "allocator" { continue }

        var_name := naming_extract_text(var_node, file_lines)
        if len(var_name) == 0 { continue }

        // Fire if LHS doesn't signal ownership.
        if strings.contains(var_name, "_owned") { continue }

        pt := ts_node_start_point(var_node)
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = int(pt.row) + 1,
            column    = int(pt.column) + 1,
            rule_id   = "C012",
            tier      = "style",
            message   = fmt.aprintf(
                "'%s' receives ownership from allocator-role proc '%s' — consider suffix '_owned' to signal caller must free",
                var_name, callee_name,
            ),
            has_fix   = true,
            fix       = fmt.aprintf("Rename '%s' to '%s_owned'", var_name, var_name),
            diag_type = .INFO,
        })
    }

    return diagnostics[:]
}

@(private)
_c012_t3_get_role :: proc(db: ^GraphDB, name: string) -> string {
    s, ok := sq.db_prepare(db.conn,
        "SELECT memory_role FROM nodes WHERE name=? AND kind='proc' LIMIT 1;")
    if !ok { return "" }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, name)
    if sq.stmt_step(&s) {
        role := sq.stmt_col_text(&s, 0)
        defer delete(role)
        return strings.clone(role)
    }
    return ""
}
