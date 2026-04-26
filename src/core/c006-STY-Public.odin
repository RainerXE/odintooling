// c006-STY-Public.odin — C006: exported symbol naming (disabled).
// Placeholder; exported naming checks are handled by C003/C007.
package core

// =============================================================================
// C006: Public procedure naming conventions
// =============================================================================
// Planned: public (exported) procs should follow consistent naming.
// Implementation deferred to M3.4+.
// =============================================================================

c006_rule :: proc() -> Rule {
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
