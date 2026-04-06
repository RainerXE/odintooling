package core

import "core:fmt"
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

// c002Matcher checks for defer free on wrong pointer
c002Matcher :: proc(file_path: string, node: ^ASTNode, ctx: ^C002AnalysisContext) -> []Diagnostic {
    diagnostics: [dynamic]Diagnostic
    
    // Track scope boundaries using stack-based approach
    is_block := strings.contains(node.node_type, "block")
    if is_block {
        // Entering a new scope - push onto stack
        append(&ctx.scope_stack, node.node_type)
        ctx.current_scope = len(ctx.scope_stack)
    }
    
    // Check for pointer allocations (make, new, etc.) using AST structure like C001
    // Look for assignment_statement with make/new calls
    if node.node_type == "assignment_statement" {
        // Check if this assignment contains a make or new call
        has_allocation_call := false
        for &child in node.children {
            if child.node_type == "call_expression" {
                has_allocation_call = true
                // Found a call expression - check if it's make or new
                // We'll extract the variable name and check the call type
                var_name := extract_lhs_var_name(node)
                if var_name != "" {
                    // Check if this is a make/new call by looking at the callee
                    if len(child.children) > 0 {
                        callee := &child.children[0]
                        callee_text := ""
                        if callee.node_type == "identifier" {
                            callee_text = callee.text
                        }
                        
                        // Check for make, new, alloc, malloc
                        if callee_text == "make" || callee_text == "new" || 
                           callee_text == "alloc" || callee_text == "malloc" {
                            fmt.println("DEBUG: Found allocation:", var_name, "via", callee_text, "at line", node.start_line)
                            c002_markAsAllocated(var_name, node.start_line, node.start_column, ctx.current_scope, ctx)
                            break
                        }
                    }
                }
            }
        }
        
        // If no allocation call found, check for reassignment
        if !has_allocation_call {
            var_name := extract_lhs_var_name(node)
            if var_name != "" {
                // This is a pure reassignment, not an allocation
                fmt.println("DEBUG: Reassigning", var_name, "at line", node.start_line, "scope", ctx.current_scope)
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
    }
    
    // Check if this node is a defer statement with free/delete
    if is_defer_cleanup(node) {
        // Extract variable name from defer free statement
        var_name := extract_var_name_from_free(node)
        if var_name != "" {
            
            // Skip analysis if we don't have an allocation record
            if var_name not_in ctx.allocations_map {
                // Skip - no allocation record
            } else {
                // Check for double free first
                diag := c002_markAsFreed(var_name, node.start_line, node.start_column, ctx.current_scope, file_path, ctx)
                if diag.message != "" {
                    // Double free detected - definite violation
                    append(&diagnostics, diag)
                } else {
                    // Check for reassignment issues - find allocation in current scope
                    if len(ctx.allocations_map[var_name]) > 0 {
                        // Find the allocation record that matches the current scope
                        found_allocation := false
                        for i in 0..<len(ctx.allocations_map[var_name]) {
                            if ctx.allocations_map[var_name][i].scope_level == ctx.current_scope {
                                allocation_info := ctx.allocations_map[var_name][i]
                                if allocation_info.is_reassigned {
                                    // Potential misuse - contextual
                                    append(&diagnostics, Diagnostic{
                                        file = file_path,
                                        line = node.start_line,
                                        column = node.start_column,
                                        rule_id = "C002",
                                        tier = "correctness",
                                        message = "Freeing reassigned pointer - this may free wrong memory (POTENTIAL)",
                                        fix = "Pointer was reassigned before free - this may free wrong memory",
                                        has_fix = true,
                                        diag_type = .CONTEXTUAL,
                                    })
                                }
                                found_allocation = true
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Debug: Show what node types we're processing
    if strings.contains(node.text, "make(") || strings.contains(node.text, "free(") {
        fmt.println("DEBUG C002: Processing node type:", node.node_type, "text:", node.text)
    }
    
    // Check children recursively
    for &child in node.children {
        child_diagnostics := c002Matcher(file_path, &child, ctx)
        for child_diag in child_diagnostics {
            if child_diag.message != "" {
                append(&diagnostics, child_diag)
            }
        }
    }
    
    // Exit scope after processing children
    if is_block && len(ctx.scope_stack) > 0 {
        pop(&ctx.scope_stack)
        ctx.current_scope = len(ctx.scope_stack)
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
    append(&existing, allocation)
    ctx.allocations_map[var_name] = existing
}

// c002_markAsFreed marks a variable as freed and detects double frees
c002_markAsFreed :: proc(var_name: string, line: int, col: int, scope_level: int, file_path: string, ctx: ^C002AnalysisContext) -> Diagnostic {
    diag_to_report: Diagnostic
    
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
                        message = "Multiple defer frees on same allocation",
                        fix = fmt.tprintf("Allocation at line %d,%d freed %d times",
                                        existing[i].line, existing[i].col, existing[i].free_count),
                        has_fix = true,
                        diag_type = .VIOLATION,
                    }
                    // Return immediately on first double-free detection
                    ctx.allocations_map[var_name] = existing
                    return diag_to_report
                }
            }
        }
        // Always write back the modified slice if no double-free detected
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
        keyword: string
        if strings.contains(text, "free(") {
            keyword = "free"
        } else {
            keyword = "delete"
        }
        
        start_idx := strings.index(text, keyword) + len(keyword) + 1
        if start_idx > len(text) || text[start_idx-1] != '(' {
            return ""
        }
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

// extract_lhs_var_name extracts variable name from left-hand side of assignment
extract_lhs_var_name :: proc(node: ^ASTNode) -> string {
    text := node.text
    
    // Pattern: variable := value or variable = value
    // Handle both declaration and assignment syntax
    if strings.contains(text, ":=") {
        parts := strings.split(text, ":=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            // Handle multi-assignment: a, b := value
            if strings.contains(var_name, ",") {
                // For now, take first variable and add comment about limitation
                // TODO: Track all variables in multi-assignment
                first_var := strings.trim(strings.split(var_name, ",")[0], " \t")
                return first_var
            }
            return var_name
        }
    } else if strings.contains(text, "=") {
        parts := strings.split(text, "=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            // Handle multi-assignment: a, b = value
            if strings.contains(var_name, ",") {
                // For now, take first variable and add comment about limitation
                // TODO: Track all variables in multi-assignment
                first_var := strings.trim(strings.split(var_name, ",")[0], " \t")
                return first_var
            }
            return var_name
        }
    }
    
    return ""
}

// is_pointer_allocation checks if node is a pointer allocation (make, new, etc.)
is_pointer_allocation :: proc(node: ^ASTNode) -> bool {
    return (strings.contains(node.node_type, "assignment") ||
            strings.contains(node.node_type, "declaration")) &&
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
    // Note: "os.free" and "mem.free" contain "free", so single check suffices
    return strings.contains(node.node_type, "defer_statement") && 
           (strings.contains(node.text, "free") || 
            strings.contains(node.text, "delete"))
}

// c002Message returns the rule message
c002Message :: proc() -> string {
    return "Defer free on wrong pointer - does not match allocation"
}

// c002FixHint returns the fix hint
c002FixHint :: proc() -> string {
    return "Ensure defer free uses the same pointer as the allocation"
}