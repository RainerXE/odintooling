package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C007: Type Naming Convention
// =============================================================================
//
// Detects type names that don't follow PascalCase convention.
// Type names should start with uppercase and use camel case.
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C007Rule creates the C007 rule
C007Rule :: proc() -> Rule {
    return Rule{
        id = "C007",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c007Matcher,
        message = c007Message,
        fix_hint = c007FixHint,
    }
}

c007Message :: proc() -> string {
    return "Type naming convention violation"
}

c007FixHint :: proc() -> string {
    return "Type names should use PascalCase (e.g., MyType)"
}

// Pattern for type naming (file-specific to avoid conflicts)
c007_type_pattern :: `^[A-Z][a-zA-Z0-9]*$`

// c007Matcher checks for type naming violations
c007Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual type naming checking
    // This is a stub implementation
    
    // Check if this is a type definition
    if node.node_type == "type_definition" {
        // Check type name against pattern
        // (This would require more sophisticated AST analysis)
        
        // For now, return empty diagnostic (stub)
        return Diagnostic{}
    }
    
    // Check children recursively
    for &child in node.children {
        diag := c007Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}