package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C004: Private Procedure Naming
// =============================================================================
//
// Detects private procedures that don't follow naming conventions.
// Private procedures should use snake_case and start with lowercase.
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C004Rule creates the C004 rule
C004Rule :: proc() -> Rule {
    return Rule{
        id = "C004",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c004Matcher,
        message = c004Message,
        fix_hint = c004FixHint,
    }
}

c004Message :: proc() -> string {
    return "Private procedure naming violation"
}

c004FixHint :: proc() -> string {
    return "Private procedures should use snake_case starting with lowercase"
}

// c004Matcher checks for private procedure naming violations
c004Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual private procedure naming checking
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
        diag := c004Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}