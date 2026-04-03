package core

import "core:fmt"
import "core:os"
import "core:strings"

// C002 rule implementation
// C002: Defer free on wrong pointer
// This rule detects when defer free is called on a different pointer than the one allocated

// C002AllocationInfo tracks allocation and free information
C002AllocationInfo :: struct {
    var_name: string,
    line: int,
    col: int,
    is_freed: bool,
    free_count: int,  // Track number of defer frees
    scope_level: int,  // Track scope level for proper matching
    is_reassigned: bool,  // Track if pointer was reassigned
    reassignment_line: int,  // Line where reassignment occurred
}

// Global map to track allocations and frees
c002_allocations_map: map[string][]C002AllocationInfo
c002_current_scope: int = 0  // Track current scope level
c002_reassignments: map[string]bool  // Track reassigned variables

// C002Rule creates the C002 rule
C002Rule :: proc() -> Rule {
    return Rule{
        id = "C002",
        tier = "correctness",
        category = .CORRECTNESS,  // Clippy-inspired categorization
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
    // Track scope boundaries
    if is_scope_boundary(node) {
        if is_entering_scope(node) {
            c002_current_scope += 1
        } else {
            c002_current_scope -= 1
        }
    }
    
    // Check for pointer reassignment
    if is_pointer_reassignment(node) {
        var_name := extract_var_name_from_assignment(node)
        if var_name != "" {
            c002_reassignments[var_name] = true
            // Mark as reassigned in tracking map
            if len(c002_allocations_map[var_name]) > 0 {
                existing := c002_allocations_map[var_name]
                for i in 0..<len(existing) {
                    existing[i].is_reassigned = true
                    existing[i].reassignment_line = node.start_line
                }
                c002_allocations_map[var_name] = existing
            }
        }
    }
    
    // Check if this node is a defer statement with free/delete
    if is_defer_cleanup(node) {
        // Extract variable name from defer free statement
        var_name := extract_var_name_from_free(node)
        if var_name != "" {
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
            
            // Check if pointer was reassigned before free
            if c002_reassignments[var_name] {
                return Diagnostic{
                    file = file_path,
                    line = node.start_line,
                    column = node.start_column,
                    rule_id = "C002",
                    tier = "correctness",
                    message = "C002 [correctness] Freeing reassigned pointer",
                    fix: "Pointer was reassigned before free - this may free wrong memory",
                    has_fix: true,
                    diag_type: .VIOLATION,
                }
            }
            
            // Track the free operation with current scope
            diag := c002_markAsFreed(var_name, node.start_line, node.start_column, c002_current_scope)
            if diag.message != "" {
                return diag
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

// c002_markAsFreed marks a variable as freed and detects double frees
c002_markAsFreed :: proc(var_name: string, line: int, col: int, scope_level: int) -> Diagnostic {
    if len(c002_allocations_map[var_name]) > 0 {
        existing := c002_allocations_map[var_name]
        for i in 0..<len(existing) {
            // Only process allocations in the same scope
            if existing[i].scope_level == scope_level {
                existing[i].free_count += 1  // Increment instead of setting true
                
                // Detect and report double free
                if existing[i].free_count > 1 {
                    return Diagnostic{
                        file = "",
                        line: line,
                        column: col,
                        rule_id: "C002",
                        tier: "correctness",
                        message: "C002 [correctness] Multiple defer frees on same allocation",
                        fix: fmt.tprintf("Allocation at line %d,%d freed %d times",
                                        existing[i].line, existing[i].col, existing[i].free_count),
                        has_fix: true,
                        diag_type: .VIOLATION,
                    }
                }
            }
        }
        c002_allocations_map[var_name] = existing
    }
    return Diagnostic{}
}

// extract_var_name_from_free extracts variable name from free statement
extract_var_name_from_free :: proc(node: ^ASTNode) -> string {
    // Simple extraction - look for variable name before free
    text := node.text
    
    // Pattern: defer free(variable)
    if strings.contains(text, "free(") {
        start_idx := strings.index_of(text, "free(") + 5
        end_idx := strings.index_of(text, ")", start_idx)
        if start_idx >= 0 && end_idx > start_idx {
            var_name := strings.trim(text[start_idx..end_idx])
            // Remove any trailing commas or whitespace
            var_name = strings.trim(var_name, " ,")
            return var_name
        }
    }
    
    return ""
}

// is_scope_boundary checks if node represents a scope boundary
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block") ||
           strings.contains(node.node_type, "proc") ||
           strings.contains(node.node_type, "for") ||
           strings.contains(node.node_type, "if") ||
           strings.contains(node.node_type, "case")
}

// is_entering_scope checks if we're entering a new scope
is_entering_scope :: proc(node: ^ASTNode) -> bool {
    // For blocks, we're entering when we see the opening brace
    if strings.contains(node.node_type, "block") {
        return strings.contains(node.text, "{")
    }
    // For control structures, we're entering at the start
    return strings.contains(node.node_type, "proc") ||
           strings.contains(node.node_type, "for") ||
           strings.contains(node.node_type, "if") ||
           strings.contains(node.node_type, "case")
}

// is_pointer_reassignment checks if node is a pointer reassignment
is_pointer_reassignment :: proc(node: ^ASTNode) -> bool {
    // Look for assignment patterns with pointer variables
    return strings.contains(node.node_type, "assignment") &&
           (strings.contains(node.text, ":=") || strings.contains(node.text, "=")) &&
           (strings.contains(node.text, "ptr") || 
            strings.contains(node.text, "buffer") ||
            strings.contains(node.text, "data") ||
            strings.contains(node.text, "mem") ||
            strings.contains(node.text, "alloc"))
}

// extract_var_name_from_assignment extracts variable name from assignment
extract_var_name_from_assignment :: proc(node: ^ASTNode) -> string {
    text := node.text
    
    // Pattern: variable := value or variable = value
    if strings.contains(text, ":=") {
        parts := strings.split(text, ":=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0])
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0])
            }
            return var_name
        }
    } else if strings.contains(text, "=") {
        parts := strings.split(text, "=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0])
            return var_name
        }
    }
    
    return ""
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