package core

// =============================================================================
// C005: Internal procedure naming conventions
// =============================================================================
// Planned: internal (unexported) procs should follow consistent naming.
// Implementation deferred to M3.4+.
// =============================================================================

C005Rule :: proc() -> Rule {
    return Rule{
        id       = "C005",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c005_message,
        fix_hint = c005_fix_hint,
    }
}

c005_message  :: proc() -> string { return "Internal procedure naming violation" }
c005_fix_hint :: proc() -> string { return "Internal procedures should use snake_case starting with lowercase" }
