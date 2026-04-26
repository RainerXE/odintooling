// c008-STY-Acronyms.odin — C008: acronym capitalisation hints (disabled).
// Placeholder for a future rule; acronym casing is intentionally flexible in Odin.
package core

// =============================================================================
// C008: Acronym consistency in identifiers
// =============================================================================
// Planned: acronyms in identifiers should be consistently cased (HTTP or http).
// Implementation deferred to M3.4+.
// =============================================================================

c008_rule :: proc() -> Rule {
    return Rule{
        id       = "C008",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c008_message,
        fix_hint = c008_fix_hint,
    }
}

c008_message  :: proc() -> string { return "Acronym consistency violation" }
c008_fix_hint :: proc() -> string { return "Use consistent acronym casing (e.g., HTTP or http)" }
