package core

import "core:fmt"
import "core:os"
import "core:strings"

// C001 rule implementation
// C001: Allocation without matching defer free in same scope
// Inspired by: Rust clippy::mem_forget

// C001Rule creates the C001 rule
C001Rule :: proc() -> Rule {
    return Rule{
        id = "C001",
        tier = "correctness",
        matcher = c001Matcher,
        message = c001Message,
        fix_hint = c001FixHint,
    }
}

// c001Matcher checks for allocations without defer free
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // Simplified implementation: Look for allocation patterns in the entire file
    // This is a heuristic approach that may have some false positives/negatives
    
    // Check if this is a call_expression node (potential allocation)
    if node.node_type == "call_expression" {
        // For now, we'll use a simple heuristic:
        // If we find an allocation keyword, assume it needs checking
        // In production, we'd do proper scope analysis
        if is_allocation_node(node) {
            // Check if file contains defer free patterns
            // This is a simplified check - real implementation needs scope analysis
            content, err := os.read_entire_file_from_path(file_path, context.allocator)
            if err == nil {
                content_str := string(content)
                defer_free_found := strings.contains(content_str, "defer free") ||
                                   strings.contains(content_str, "defer delete") ||
                                   strings.contains(content_str, "defer os.free") ||
                                   strings.contains(content_str, "defer mem.free")
                
                if !defer_free_found {
                    return Diagnostic{
                        file = file_path,
                        line = node.start_line,
                        column = node.start_column,
                        rule_id = "C001",
                        tier = "correctness",
                        message = "Allocation without matching defer free in same scope",
                        fix = "Add defer free() immediately after allocation",
                        has_fix = true,
                    }
                }
            }
        }
    }
    
    // Check children recursively for allocations
    for &child in node.children {
        diag := c001Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}

// is_allocation_node checks if a node represents an allocation
is_allocation_node :: proc(node: ^ASTNode) -> bool {
    // Check node type first - call_expression nodes are likely allocations
    if node.node_type == "call_expression" {
        return true  // We'll check the actual function name in the parent context
    }
    
    // Also check for identifier nodes that might be allocation functions
    if node.node_type == "identifier" {
        return node.text == "make" || node.text == "new" || node.text == "malloc" || 
               node.text == "calloc" || node.text == "realloc"
    }
    
    return false
}

// has_matching_defer_free checks if allocation has proper cleanup
has_matching_defer_free :: proc(node: ^ASTNode) -> bool {
    // Check if this node or its siblings contain defer free statements
    // This is a simplified approach - full implementation would need:
    // 1. Extract the allocated variable name from the assignment
    // 2. Search through sibling nodes for defer statements
    // 3. Parse defer statements to find free/delete calls
    // 4. Match variable names between allocation and free
    
    // For now, we'll do a simple text search in the node's text
    // This catches most cases but may have false positives/negatives
    return strings.contains(node.text, "defer free") ||
           strings.contains(node.text, "defer delete") ||
           strings.contains(node.text, "defer os.free") ||
           strings.contains(node.text, "defer mem.free")
}

// c001Message returns the rule message
c001Message :: proc() -> string {
    return "Allocation without matching defer free in same scope"
}

// c001FixHint returns the fix hint
c001FixHint :: proc() -> string {
    return "Add defer free() immediately after allocation"
}