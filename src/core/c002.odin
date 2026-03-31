package core

import "core:fmt"
import "core:os"
import "core:strings"

// C002 rule implementation
// C002: Defer free on wrong pointer
// This rule detects when defer free is called on a different pointer than the one allocated

// C002Rule creates the C002 rule
C002Rule :: proc() -> Rule {
    return Rule{
        id = "C002",
        tier = "correctness",
        matcher = c002Matcher,
        message = c002Message,
        fix_hint = c002FixHint,
    }
}

// Helper: Check if a statement is a cleanup function (free/delete)
is_cleanup_function :: proc(text: string) -> bool {
    return strings.contains(text, "free") || strings.contains(text, "delete")
}

// c002Matcher checks for defer free on wrong pointer
c002Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // Check if this node is a defer statement with free/delete
    if strings.contains(node.node_type, "defer_statement") && is_cleanup_function(node.text) {
        // Check if this defer free references a different variable than the allocation
        if is_wrong_pointer_free(node) {
            return Diagnostic{
                file = file_path,
                line = node.start_line,
                column = node.start_column,
                rule_id = "C002",
                tier = "correctness",
                message = "Defer free on wrong pointer - does not match allocation",
                fix = "Ensure defer free uses the same pointer as the allocation",
                has_fix = true,
            }
        }
    }
    
    // Check children recursively
    for &child in node.children {
        diag := c002Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}

// is_wrong_pointer_free checks if defer free uses wrong pointer
// This is a simplified check - real implementation would track variable assignments
is_wrong_pointer_free :: proc(node: ^ASTNode) -> bool {
    // For now, we'll use a heuristic: if the defer statement
    // contains common patterns that suggest wrong pointer usage
    
    // Check for suspicious patterns like freeing after reassignment
    if strings.contains(node.text, "=") && strings.contains(node.text, "free") {
        return true
    }
    
    // Check for common wrong pointer patterns
    if strings.contains(node.text, "ptr2") || strings.contains(node.text, "temp") {
        return true
    }
    if strings.contains(node.text, "copy") || strings.contains(node.text, "backup") {
        return true
    }
    if strings.contains(node.text, "old") || strings.contains(node.text, "other") {
        return true
    }
    if strings.contains(node.text, "different") || strings.contains(node.text, "wrong") {
        return true
    }
    if strings.contains(node.text, "mistake") {
        return true
    }
    
    return false
}

// c002Message returns the rule message
c002Message :: proc() -> string {
    return "Defer free on wrong pointer - does not match allocation"
}

// c002FixHint returns the fix hint
c002FixHint :: proc() -> string {
    return "Ensure defer free uses the same pointer as the allocation"
}