package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C003: Inconsistent Naming Conventions
// =============================================================================
//
// Detects violations of Odin naming conventions:
// - Variables: snake_case
// - Types: PascalCase
// - Procedures: snake_case
// - Constants: SCREAMING_SNAKE_CASE
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C003Rule creates the C003 rule
C003Rule :: proc() -> Rule {
    return Rule{
        id = "C003",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c003Matcher,
        message = c003Message,
        fix_hint = c003FixHint,
    }
}

c003Message :: proc() -> string {
    return "Naming convention violation"
}

c003FixHint :: proc() -> string {
    return "Use snake_case for variables, PascalCase for types"
}

// Pattern matching for naming conventions (file-specific to avoid conflicts)
c003_variable_pattern :: `^[a-z][a-z0-9_]*$`
c003_type_pattern :: `^[A-Z][a-zA-Z0-9]*$`
c003_procedure_pattern :: `^[a-z][a-z0-9_]*$`
c003_constant_pattern :: `^[A-Z][A-Z0-9_]*$`

// c003Matcher checks for naming convention violations
c003Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual naming convention checking
    // This is a stub implementation
    
    // Check if this is an identifier node
    if node.node_type == "identifier" {
        text := node.text
        
        // Determine what kind of identifier this is
        // (This would require more sophisticated AST analysis)
        
        // For now, return empty diagnostic (stub)
        return Diagnostic{}
    }
    
    // Check children recursively
    for &child in node.children {
        diag := c003Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}