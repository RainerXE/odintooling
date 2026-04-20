package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C018: Proc naming must reflect visibility  (opt-in)
// =============================================================================
//
// When this rule is enabled, proc naming follows the visibility convention:
//
//   @(private) proc  →  snake_case   (internal implementation detail)
//   public proc      →  PascalCase   (API surface, exported symbol)
//
// Violation:   @(private) InitParser :: proc() {}   ← PascalCase private proc
// Violation:   set_shader_value :: proc() {}         ← snake_case public proc
// OK:          @(private) init_parser :: proc() {}
// OK:          SetShaderValue :: proc() {}
//
// NOTE: C018 directly conflicts with C003 (which requires ALL procs to be
// snake_case). Disable C003 when enabling C018:
//   [rules]
//   C003 = { level = "off" }
//   C018 = { level = "warn", category = "style" }
//
// Category: STYLE (opt-in, warn tier)
// =============================================================================

// decl_node_is_private returns true if the declaration node that owns name_node
// has an @(private) or @(private="file") attribute. Works for any declaration
// kind (proc, const, var) — does not check the parent node type.
decl_node_is_private :: proc(name_node: TSNode, file_lines: []string) -> bool {
    decl := ts_node_parent(name_node)
    if ts_node_is_null(decl) { return false }

    child_count := int(ts_node_child_count(decl))
    for i in 0..<child_count {
        child := ts_node_child(decl, u32(i))
        if string(ts_node_type(child)) != "attributes" { continue }

        attr_count := int(ts_node_child_count(child))
        for j in 0..<attr_count {
            attr := ts_node_child(child, u32(j))
            if string(ts_node_type(attr)) != "attribute" { continue }

            id_count := int(ts_node_child_count(attr))
            for k in 0..<id_count {
                id_node := ts_node_child(attr, u32(k))
                if naming_extract_text(id_node, file_lines) == "private" {
                    return true
                }
            }
        }
    }
    return false
}

// proc_node_is_private is a convenience alias kept for backward compatibility.
proc_node_is_private :: proc(proc_name_node: TSNode, file_lines: []string) -> bool {
    return decl_node_is_private(proc_name_node, file_lines)
}

// c018_scm_run processes @proc_name captures from naming_rules.scm.
// Reuses the same capture as C003 — no additional SCM pattern needed.
c018_scm_run :: proc(
    file_path: string,
    result_captures: map[string]TSNode,
    file_lines: []string,
) -> (Diagnostic, bool) {
    proc_node, ok := result_captures["proc_name"]
    if !ok { return {}, false }

    name := naming_extract_text(proc_node, file_lines)
    if len(name) == 0 { return {}, false }

    is_private := proc_node_is_private(proc_node, file_lines)
    pt := ts_node_start_point(proc_node)

    if is_private {
        // Private proc must be snake_case (no uppercase)
        if c016_is_snake_case(name) { return {}, false }
        return Diagnostic{
            file      = file_path,
            line      = int(pt.row) + 1,
            column    = int(pt.column) + 1,
            rule_id   = "C018",
            tier      = "style",
            message   = fmt.aprintf(
                "@(private) proc '%s' should be snake_case (internal symbol)",
                name,
            ),
            has_fix   = true,
            fix       = fmt.aprintf("Rename '%s' to snake_case equivalent", name),
            diag_type = .VIOLATION,
        }, true
    }

    // Public proc must be PascalCase (starts uppercase)
    if len(name) > 0 && name[0] >= 'A' && name[0] <= 'Z' { return {}, false }
    return Diagnostic{
        file      = file_path,
        line      = int(pt.row) + 1,
        column    = int(pt.column) + 1,
        rule_id   = "C018",
        tier      = "style",
        message   = fmt.aprintf(
            "Public proc '%s' should be PascalCase (API surface symbol)",
            name,
        ),
        has_fix   = true,
        fix       = fmt.aprintf("Rename '%s' to PascalCase equivalent (e.g. capitalise each word, remove underscores)", name),
        diag_type = .VIOLATION,
    }, true
}
