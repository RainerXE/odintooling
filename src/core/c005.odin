package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C005: Internal Procedure Naming
// =============================================================================
//
// Detects internal procedures that don't follow naming conventions.
// Internal procedures should use snake_case and start with lowercase.
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C005Rule creates the C005 rule
C005Rule :: proc() -> Rule {
    return Rule{
        id = "C005",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c005Matcher,
        message = c005Message,
        fix_hint = c005FixHint,
    }
}

c005Message :: proc() -> string {
    return "Internal procedure naming violation"
}

c005FixHint :: proc() -> string {
    return "Internal procedures should use snake_case starting with lowercase"
}

// c005Matcher checks for internal procedure naming violations
c005Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual internal procedure naming checking
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
        diag := c005Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}