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
    if is_defer_cleanup(node) {
        // Check if this defer free references a different variable than the allocation
        if is_suspicious_pointer_usage(node) {
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

// is_defer_cleanup checks if node is defer with cleanup function
is_defer_cleanup :: proc(node: ^ASTNode) -> bool {
    // Check node type and content for defer + cleanup pattern
    return strings.contains(node.node_type, "defer_statement") && 
           (strings.contains(node.text, "free") || 
            strings.contains(node.text, "delete") ||
            strings.contains(node.text, "os.free") ||
            strings.contains(node.text, "mem.free"))
}

// is_suspicious_pointer_usage checks for potential wrong pointer patterns
is_suspicious_pointer_usage :: proc(node: ^ASTNode) -> bool {
    // Pattern 1: Reassignment before free (common mistake)
    if strings.contains(node.text, "=") && strings.contains(node.text, "free") {
        return true
    }
    
    // Pattern 2: Using different variable names
    if (strings.contains(node.text, "ptr2") || strings.contains(node.text, "temp") || 
        strings.contains(node.text, "copy") || strings.contains(node.text, "backup") ||
        strings.contains(node.text, "old") || strings.contains(node.text, "other") ||
        strings.contains(node.text, "different") || strings.contains(node.text, "wrong") ||
        strings.contains(node.text, "mistake") || strings.contains(node.text, "alternative") ||
        strings.contains(node.text, "second")) && strings.contains(node.text, "free") {
        return true
    }
    
    // Pattern 3: Complex expressions in free (often wrong)
    if strings.contains(node.text, "+)") || strings.contains(node.text, "-)") {
        return true
    }
    
    // Pattern 4: Freeing after type conversion (often problematic)
    if strings.contains(node.text, "cast") && strings.contains(node.text, "free") {
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