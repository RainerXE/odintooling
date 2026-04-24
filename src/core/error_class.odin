package core

// rule_id_to_error_class maps a rule ID to its stable error-class string.
// Format: {tier}_{category}_{detail}
// Returns "unknown" for unrecognised rule IDs.
rule_id_to_error_class :: proc(rule_id: string) -> string {
    switch rule_id {
    // ── Correctness ──────────────────────────────────────────────────────────
    case "C001": return "correctness_memory_leak"
    case "C002": return "correctness_double_free"
    case "C009": return "migration_deprecated_import"
    case "C010": return "migration_deprecated_fmt"
    case "C011": return "ffi_resource_leak"
    case "C101": return "correctness_context_integrity"
    case "C201": return "correctness_unchecked_result"
    case "C203": return "correctness_defer_scope_trap"
    // ── Style ─────────────────────────────────────────────────────────────────
    case "C003": return "style_naming_proc"
    case "C007": return "style_naming_type"
    case "C012": return "style_ownership_naming"
    case "C016": return "style_naming_local_var"
    case "C017": return "style_naming_pkg_var"
    case "C018": return "style_naming_visibility"
    case "C019": return "style_naming_type_marker"
    // ── Dead code ─────────────────────────────────────────────────────────────
    case "C014": return "dead_code_unused_proc"
    case "C015": return "dead_code_unused_const"
    // ── Structural ────────────────────────────────────────────────────────────
    case "B001": return "structure_unmatched_brace"
    case "B002": return "structure_package_name"
    case "B003": return "structure_subfolder_clash"
    }
    return "unknown"
}
