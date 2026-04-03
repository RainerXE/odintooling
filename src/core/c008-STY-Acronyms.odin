#+feature dynamic-literals
package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C008: Acronym Consistency
// =============================================================================
//
// Detects inconsistent acronym usage in identifiers.
// Acronyms should be consistently cased (e.g., HTTP or http, not Http).
//
// Category: STYLE (Clippy-inspired)
// =============================================================================

// C008Rule creates the C008 rule
C008Rule :: proc() -> Rule {
    return Rule{
        id = "C008",
        tier = "style",
        category = .STYLE,  // Clippy-inspired categorization
        matcher = c008Matcher,
        message = c008Message,
        fix_hint = c008FixHint,
    }
}

c008Message :: proc() -> string {
    return "Acronym consistency violation"
}

c008FixHint :: proc() -> string {
    return "Use consistent acronym casing (e.g., HTTP or http)"
}

// Common acronyms to check (stub - will be implemented properly later)
// common_acronyms :: [dynamic]string

// c008Matcher checks for acronym consistency violations
c008Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // TODO: Implement actual acronym consistency checking
    // This is a stub implementation
    
    // Check if this is an identifier node
    if node.node_type == "identifier" {
        text := node.text
        
        // Check for common acronyms in mixed case
        // (This would require more sophisticated analysis)
        
        // For now, return empty diagnostic (stub)
        return Diagnostic{}
    }
    
    // Check children recursively
    for &child in node.children {
        diag := c008Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}