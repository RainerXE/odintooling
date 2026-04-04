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

// C002AnalysisContext holds analysis state for a single file
C002AnalysisContext :: struct {
    allocations_map: map[string][dynamic]C002AllocationInfo,
    current_scope: int,
    reassignments: map[string]bool,
    scope_stack: [dynamic]string,  // Track entered scopes for proper exit detection
}

// create_c002_context creates a new analysis context
create_c002_context :: proc() -> C002AnalysisContext {
    return C002AnalysisContext{
        allocations_map = {},
        current_scope = 0,
        reassignments = {},
        scope_stack = {},
    }
}

// C002Rule creates the C002 rule
// IMPORTANT: c002Matcher is NOT stored in the Rule.matcher field due to signature mismatch
// It requires a context parameter and is called directly from main.odin.
// The matcher field is explicitly set to nil - any code using Rule.matcher must check for nil.
C002Rule :: proc() -> Rule {
    return Rule{
        id = "C002",
        tier = "correctness",
        category = .CORRECTNESS,  // Clippy-inspired categorization
        matcher = nil,  // ⚠️ c002Matcher has different signature, called directly from main.odin
        message = c002Message,
        fix_hint = c002FixHint,
    }
}

// Note: is_cleanup_function was removed as it was unused
// The functionality is handled directly in is_defer_cleanup

// c002Matcher checks for defer free on wrong pointer
c002Matcher :: proc(file_path: string, node: ^ASTNode, ctx: ^C002AnalysisContext) -> []Diagnostic {
    diagnostics: [dynamic]Diagnostic
    
    // Track scope boundaries using stack-based approach
    if is_scope_boundary(node) {
        if is_entering_scope(node) {
            // Entering a new scope - push onto stack
            ctx.scope_stack = append(ctx.scope_stack, node.node_type)
            ctx.current_scope = len(ctx.scope_stack)
        } else {
            // Exiting a scope - pop from stack
            if len(ctx.scope_stack) > 0 {
                ctx.scope_stack = ctx.scope_stack[0..<len(ctx.scope_stack)]
                ctx.current_scope = len(ctx.scope_stack)
            }
        }
    }
    
    // Check for pointer allocations (make, new, etc.)
    if is_pointer_allocation(node) {
        var_name := extract_var_name_from_allocation(node)
        if var_name != "" {
            c002_markAsAllocated(var_name, node.start_line, node.start_column, ctx.current_scope, ctx)
        }
    }
    
    // Check for pointer reassignment
    if is_pointer_reassignment(node) {
        var_name := extract_var_name_from_assignment(node)
        if var_name != "" {
            ctx.reassignments[var_name] = true
            // Mark as reassigned in tracking map
            if len(ctx.allocations_map[var_name]) > 0 {
                existing := ctx.allocations_map[var_name]
                for i in 0..<len(existing) {
                    existing[i].is_reassigned = true
                    existing[i].reassignment_line = node.start_line
                }
                ctx.allocations_map[var_name] = existing
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
                diagnostics = append(diagnostics, Diagnostic{
                    file = file_path,
                    line = node.start_line,
                    column = node.start_column,
                    rule_id = "C002",
                    tier = "correctness",
                    message = "Freeing wrong pointer - does not match allocation",
                    fix = "Ensure defer free uses the same pointer as the allocation",
                    has_fix = true,
                })
            }
            
            // Check if pointer was reassigned before free
            if ctx.reassignments[var_name] {
                diagnostics = append(diagnostics, Diagnostic{
                    file = file_path,
                    line = node.start_line,
                    column = node.start_column,
                    rule_id = "C002",
                    tier = "correctness",
                    message = "Freeing reassigned pointer - this may free wrong memory",
                    fix = "Pointer was reassigned before free - this may free wrong memory",
                    has_fix = true,
                    diag_type = .VIOLATION,
                })
            }
            
            // Track the free operation with current scope
            diag := c002_markAsFreed(var_name, node.start_line, node.start_column, ctx.current_scope, file_path, ctx)
            if diag.message != "" {
                diagnostics = append(diagnostics, diag)
            }
        }
    }
    
    // Check children recursively
    for &child in node.children {
        child_diagnostics := c002Matcher(file_path, &child, ctx)
        for child_diag in child_diagnostics {
            if child_diag.message != "" {
                diagnostics = append(diagnostics, child_diag)
            }
        }
    }
    
    return diagnostics[:]  // Convert dynamic array to slice for return
}

// c002_markAsAllocated tracks a new pointer allocation
c002_markAsAllocated :: proc(var_name: string, line: int, col: int, scope_level: int, ctx: ^C002AnalysisContext) {
    allocation := C002AllocationInfo{
        var_name = var_name,
        line = line,
        col = col,
        is_freed = false,
        free_count = 0,
        scope_level = scope_level,
        is_reassigned = false,
        reassignment_line = 0,
    }
    
    // Use proper map key existence check instead of len == 0
    if var_name not_in ctx.allocations_map {
        ctx.allocations_map[var_name] = make([dynamic]C002AllocationInfo)
    }
    
    existing := ctx.allocations_map[var_name]
    existing = append(existing, allocation)
    ctx.allocations_map[var_name] = existing
}

// c002_markAsFreed marks a variable as freed and detects double frees
c002_markAsFreed :: proc(var_name: string, line: int, col: int, scope_level: int, file_path: string, ctx: ^C002AnalysisContext) -> Diagnostic {
    var diag_to_report: Diagnostic
    
    if len(ctx.allocations_map[var_name]) > 0 {
        existing := ctx.allocations_map[var_name]
        for i in 0..<len(existing) {
            // Only process allocations in the same scope
            if existing[i].scope_level == scope_level {
                existing[i].free_count += 1  // Increment instead of setting true
                
                // Detect and report double free
                if existing[i].free_count > 1 {
                    diag_to_report = Diagnostic{
                        file = file_path,  // Use passed file path
                        line = line,
                        column = col,
                        rule_id = "C002",
                        tier = "correctness",
                        message = "C002 [correctness] Multiple defer frees on same allocation",
                        fix = fmt.tprintf("Allocation at line %d,%d freed %d times",
                                        existing[i].line, existing[i].col, existing[i].free_count),
                        has_fix = true,
                        diag_type = .VIOLATION,
                    }
                }
            }
        }
        // Always write back the modified slice, even if we detected a double-free
        ctx.allocations_map[var_name] = existing
    }
    return diag_to_report
}

// extract_var_name_from_free extracts variable name from free/delete statement
extract_var_name_from_free :: proc(node: ^ASTNode) -> string {
    // Simple extraction - look for variable name in free/delete calls
    text := node.text
    
    // Pattern: defer free(variable) or defer delete(variable)
    if strings.contains(text, "free(") || strings.contains(text, "delete(") {
        var keyword: string
        if strings.contains(text, "free(") {
            keyword = "free"
        } else {
            keyword = "delete"
        }
        
        start_idx := strings.index(text, keyword + "(") + len(keyword) + 1
        // Find closing parenthesis after start_idx
        rest := text[start_idx:]
        rel_idx := strings.index(rest, ")")
        if rel_idx >= 0 {
            end_idx := start_idx + rel_idx
            if start_idx >= 0 && end_idx > start_idx {
                var_name := strings.trim(text[start_idx:end_idx], " \t")
                // Remove any trailing commas or whitespace
                var_name = strings.trim(var_name, " ,")
                return var_name
            }
        }
    }
    
    return ""
}

// is_pointer_allocation checks if node is a pointer allocation (make, new, etc.)
is_pointer_allocation :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "call_expression") &&
           (strings.contains(node.text, "make(") || 
            strings.contains(node.text, "new(") ||
            strings.contains(node.text, "alloc(") ||
            strings.contains(node.text, "malloc("))
}

// extract_var_name_from_allocation extracts variable name from allocation
extract_var_name_from_allocation :: proc(node: ^ASTNode) -> string {
    text := node.text
    
    // Pattern: variable := make(...) or variable = make(...)
    // Look for assignment before the allocation call
    if strings.contains(text, ":=") {
        parts := strings.split(text, ":=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            return var_name
        }
    } else if strings.contains(text, "=") {
        // Handle variable = make(...) pattern
        // Look for the assignment target before the =
        parts := strings.split(text, "=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            
            // Handle multi-assignment: a, b = make(...)
            if strings.contains(var_name, ",") {
                // For now, take first variable and add comment about limitation
                // TODO: Track all variables in multi-assignment
                first_var := strings.trim(strings.split(var_name, ",")[0], " \t")
                return first_var
            }
            
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            return var_name
        }
    }
    
    return ""
}

// is_scope_boundary checks if node represents a scope boundary
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    // Track actual scope containers (blocks)
    return strings.contains(node.node_type, "block")
}

// is_entering_scope checks if we're entering a new scope
is_entering_scope :: proc(node: ^ASTNode) -> bool {
    // For blocks, we're entering when we see the opening brace
    // Note: This is a heuristic. Tree-sitter typically doesn't include {
    // in block node text, so we rely on the scope stack for proper tracking.
    return strings.contains(node.node_type, "block")
}

// is_pointer_reassignment checks if node is a pointer reassignment
is_pointer_reassignment :: proc(node: ^ASTNode) -> bool {
    // Rely on node type alone since we're already checking for "assignment"
    // This avoids false positives from != and == operators
    return strings.contains(node.node_type, "assignment")
}

// extract_var_name_from_assignment extracts variable name from assignment
extract_var_name_from_assignment :: proc(node: ^ASTNode) -> string {
    text := node.text
    
    // Pattern: variable := value or variable = value
    if strings.contains(text, ":=") {
        parts := strings.split(text, ":=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            return var_name
        }
    } else if strings.contains(text, "=") {
        parts := strings.split(text, "=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
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
// Uses structural analysis instead of name blocklisting
is_suspicious_pointer_usage :: proc(node: ^ASTNode) -> bool {
    // Pattern 1: Complex expressions in free (often wrong)
    // Check for arithmetic operations with proper spacing
    if strings.contains(node.text, "+ ") || strings.contains(node.text, "- ") ||
       strings.contains(node.text, "* ") || strings.contains(node.text, "/ ") {
        return true
    }
    
    // Pattern 2: Freeing after type conversion (often problematic)
    if strings.contains(node.text, "cast") && strings.contains(node.text, "free") {
        return true
    }
    
    // Note: Removed Pattern 3 (reassignment detection) since it's redundant
    // with the ctx.reassignments check. Also removed name-based blocklisting
    // (ptr2, temp, copy, etc.) to avoid false positives.
    
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