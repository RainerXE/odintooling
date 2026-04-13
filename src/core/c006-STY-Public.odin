package core

// =============================================================================
// C006: Public procedure naming conventions
// =============================================================================
// Planned: public (exported) procs should follow consistent naming.
// Implementation deferred to M3.4+.
// =============================================================================

C006Rule :: proc() -> Rule {
    return Rule{
        id       = "C006",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c006_message,
        fix_hint = c006_fix_hint,
    }
}

c006_message  :: proc() -> string { return "Public procedure naming violation" }
c006_fix_hint :: proc() -> string { return "Public procedures should use snake_case starting with lowercase" }
