package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C006: Public Procedure Naming
// =============================================================================
//
// Detects public procedures that don't follow naming conventions.
// Public procedures should use snake_case and start with lowercase.
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C006Rule creates the C006 rule
C006Rule :: proc() -> Rule {
    return Rule{
        id = "C006",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c006Matcher,
        message = c006Message,
        fix_hint = c006FixHint,
    }
}

c006Message :: proc() -> string {
    return "Public procedure naming violation"
}

c006FixHint :: proc() -> string {
    return "Public procedures should use snake_case starting with lowercase"
}

// c006Matcher checks for public procedure naming violations
c006Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual public procedure naming checking
    // This is a stub implementation
    
    // Check if this is a procedure definition
    if node.node_type == "procedure_definition" {
        // Check visibility and naming
        // (This would require more sophisticated AST analysis)
        
        // For now, return empty diagnostic (stub)
        return Diagnostic{}
    }
    
    // Check children recursively
    for &child in node.children {
        diag := c006Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}