package core

// =============================================================================
// C004: Private procedure naming conventions
// =============================================================================
// Planned: private procs (file-scope or package-scope) should follow
// consistent naming. Implementation deferred to M3.4+.
// =============================================================================

c004_rule :: proc() -> Rule {
    return Rule{
        id       = "C004",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c004_message,
        fix_hint = c004_fix_hint,
    }
}

c004_message  :: proc() -> string { return "Private procedure naming violation" }
c004_fix_hint :: proc() -> string { return "Private procedures should use camelCase or snake_case" }
