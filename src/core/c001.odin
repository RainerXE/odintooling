package core

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math"

// Helper functions for min/max
min :: proc(a, b: int) -> int {
    if a < b {
        return a
    }
    return b
}

max :: proc(a, b: int) -> int {
    if a > b {
        return a
    }
    return b
}

// C001 rule implementation
// C001: Allocation without matching defer free in same scope
// Inspired by: Rust clippy::mem_forget

// C001ScopeContext :: struct for block-level analysis
C001ScopeContext :: struct {
    allocations: [dynamic]AllocationInfo,
    defers:      [dynamic]DeferInfo,
    has_arena:   bool,
    returns_var: map[string]bool,
    is_performance_critical: bool,
}

AllocationInfo :: struct {
    var_name: string,
    line:     int,
    col:      int,
}

DeferInfo :: struct {
    freed_var: string,
}

// C001Rule creates the C001 rule
C001Rule :: proc() -> Rule {
    return Rule{
        id = "C001",
        tier = "correctness",
        matcher = c001MatcherWrapper,  // Use wrapper for compatibility
        message = c001Message,
        fix_hint = c001FixHint,
    }
}

// c001Matcher is the main multi-diagnostic matcher (used by main.odin directly)
// c001Matcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic  // Already defined above

// c001MatcherWrapper maintains compatibility with single Diagnostic interface
c001MatcherWrapper :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    diagnostics := c001Matcher(file_path, node)
    if len(diagnostics) > 0 {
        return diagnostics[0]
    }
    return Diagnostic{}
}

// c001Matcher checks for allocations without defer free
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic {
    all_diagnostics: [dynamic]Diagnostic
    
    // Check if this is a block node (tree-sitter uses "block", not "block_statement")
    if node.node_type == "block" {
        // Check block for C001 violations
        diagnostics := check_block_for_c001(node, file_path)
        if len(diagnostics) > 0 {
            for diag in diagnostics {
                append(&all_diagnostics, diag)
            }
        }
    }
    
    // Recursively check children for block nodes
    for &child in node.children {
        child_diagnostics := c001Matcher(file_path, &child)
        if len(child_diagnostics) > 0 {
            for diag in child_diagnostics {
                append(&all_diagnostics, diag)
            }
        }
    }
    
    return all_diagnostics[:]
}

// check_block_for_c001 checks a block for C001 violations
check_block_for_c001 :: proc(block: ^ASTNode, file_path: string) -> []Diagnostic {
    ctx := C001ScopeContext{}
    
    // Check if this block is in performance-critical code
    ctx.is_performance_critical = is_performance_critical_block(block, file_path)
    // Debug: Print performance critical status
    // fmt.printf("Block at line %d: performance_critical = %v\n", block.start_line, ctx.is_performance_critical)
    
    // Collect allocations and defers in this block
    for &child in block.children {
        if is_allocation_assignment(&child, file_path) {
            var_name := extract_lhs_name(&child)
            if var_name != "" {
                // Check if allocation uses non-default allocator
                if uses_non_default_allocator(&child, file_path) {
                    continue  // Skip allocations with custom allocators
                }
                
                // Check if this is a global variable assignment
                if is_global_assignment(&child) {
                    continue  // Skip global variable initializations
                }
                
                // Check if there's manual cleanup in the same block
                if has_manual_cleanup(&child, block) {
                    continue  // Skip allocations with explicit cleanup
                }
                
                // Check if this is a slice allocation with defer delete
                if has_defer_delete_for_slice(var_name, block) {
                    continue  // Skip slice allocations with defer delete
                }
                
                append(&ctx.allocations, AllocationInfo{
                    var_name = var_name,
                    line = child.start_line,
                    col = child.start_column,
                })
            }
        }
        if is_defer_free(&child) {
            freed := extract_freed_var_name(&child)
            if freed != "" {
                append(&ctx.defers, DeferInfo{freed_var = freed})
            }
        }
        if changes_context_allocator(&child) {
            ctx.has_arena = true
        }
        if is_return_statement(&child) {
            extract_returned_vars(&child, &ctx.returns_var)
        }
    }
    
    // Skip if context.allocator is reassigned
    if ctx.has_arena {
        return {}
    }
    
    // Note: We no longer skip performance-critical code entirely
    // Instead, we'll detect it but provide different messaging
    // if ctx.is_performance_critical {
    //     return {}
    // }
    
    // Check allocations against defers
    diagnostics: [dynamic]Diagnostic
    defer_frees := make(map[string]bool)
    for defer_info in ctx.defers {
        defer_frees[defer_info.freed_var] = true
    }
    
    for alloc in ctx.allocations {
        // Skip if variable is returned
        if alloc.var_name in ctx.returns_var {
            continue
        }
        
        // Skip if variable is defer-freed
        if alloc.var_name in defer_frees {
            continue
        }
        
        // Check if allocation uses non-default allocator
        // Note: This check would require the original AST node, not just AllocationInfo
        // For now, we'll skip this check as it requires more complex analysis
        // if uses_non_default_allocator(allocation_node) {
        //     continue
        // }
        
        // Fire diagnostic
        message_text := "Allocation without matching defer free in same scope"
        fix_text := "Add defer free() immediately after allocation"
        diag_type := DiagnosticType.VIOLATION
        
        // Add context if this is performance-critical code
        if ctx.is_performance_critical {
            message_text = "Allocation without matching defer free in same scope"
            fix_text = "Add defer free() immediately after allocation // Intentional? Performance marker detected"
            diag_type = DiagnosticType.CONTEXTUAL
        }
        
        append(&diagnostics, Diagnostic{
            file = file_path,
            line = alloc.line,
            column = alloc.col,
            rule_id = "C001",
            tier = "correctness",
            message = message_text,
            fix = fix_text,
            has_fix = true,
            diag_type = diag_type,
        })
    }
    
    return diagnostics[:]
}

// is_allocation_assignment checks if node is an allocation assignment
is_allocation_assignment :: proc(node: ^ASTNode, file_path: string) -> bool {
    // Accept both := (short_var_decl) and = (assignment_statement)
    if node.node_type != "short_var_decl" && node.node_type != "assignment_statement" {
        return false
    }
    
    // Check if LHS contains field access (skip field assignments)
    has_field_access := false
    for &child in node.children {
        if child.node_type == "selector_expression" {
            has_field_access = true
            break
        }
    }
    if has_field_access {
        return false
    }
    
    // Check if RHS is a call to make/new
    for &child in node.children {
        if child.node_type == "call_expression" {
            for &grandchild in child.children {
                if grandchild.node_type == "identifier" {
                    // Read source file to get actual text
                    content, err := os.read_entire_file_from_path(file_path, context.allocator)
                    if err == nil {
                        content_str := string(content)
                        // Calculate the actual byte position
                        // For simplicity, let's find the line and then the column within that line
                        lines := strings.split(content_str, "\n")
                        if grandchild.start_line - 1 < len(lines) {
                            line_content := lines[grandchild.start_line - 1]
                            if grandchild.start_column - 1 < len(line_content) {
                                // Extract text starting from the column position
                                remaining := line_content[grandchild.start_column - 1:]
                                // Check if it starts with "make" or "new"
                                if strings.has_prefix(remaining, "make") || strings.has_prefix(remaining, "new") {
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return false
}

// has_defer_delete_for_slice checks if there's a defer delete for a slice allocation
has_defer_delete_for_slice :: proc(var_name: string, block: ^ASTNode) -> bool {
    // Look for defer delete(var_name) in the same block
    for &child in block.children {
        if child.node_type == "defer_statement" {
            for &grandchild in child.children {
                if grandchild.node_type == "call_expression" {
                    for &greatgrandchild in grandchild.children {
                        if greatgrandchild.node_type == "identifier" && greatgrandchild.text == "delete" {
                            // Check if the argument is our variable
                            for &arg in grandchild.children {
                                if arg.node_type == "identifier" && arg.text == var_name {
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return false
}

// is_performance_critical_block checks if a block is in performance-critical code
is_performance_critical_block :: proc(block: ^ASTNode, file_path: string) -> bool {
    // Read source file to get actual text
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return false
    }
    content_str := string(content)
    lines := strings.split(content_str, "\n")
    
    // Check for performance-critical comments in nearby lines
    start_line := max(0, block.start_line - 5)
    end_line := min(len(lines) - 1, block.end_line + 5)
    
    for i in start_line..=end_line {
        if i < len(lines) {
            line_content := lines[i]
            
            // Debug: Print what we're checking
            // fmt.printf("Checking line %d: '%s'\n", i+1, line_content)
            
            // Look for EXACT performance-critical markers ONLY
            // Be very strict to avoid false positives from substrings
            
            // Only match these specific, unambiguous patterns:
            // Check for // PERF: but not // // PERF: (commented out markers)
            if strings.contains(line_content, "// PERF:") && !strings.contains(line_content, "// // PERF:") {
                return true
            }
            if strings.contains(line_content, "// PERFORMANCE:") {
                return true
            }
            if strings.contains(line_content, "// HOT_PATH") {
                return true
            }
            if strings.contains(line_content, "// BENCHMARK") {
                return true
            }
            if strings.contains(line_content, "// OPTIMIZED") {
                return true
            }
            if strings.contains(line_content, "// FASTPATH") {
                return true
            }
            if strings.contains(line_content, "// HOT PATH") {
                return true
            }
            
            // Special case: PERF: at start of trimmed comment (not part of other words)
            trimmed := strings.trim(line_content, " \t")
            if strings.has_prefix(trimmed, "// PERF:") {
                return true
            }
        }
    }
    
    // Check if this is in a function with performance-critical naming
    // We'd need to walk up the AST to find the containing function
    // For now, we'll skip this more complex analysis
    
    return false
}

// extract_lhs_name extracts the variable name from LHS of assignment
extract_lhs_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "identifier" {
            return child.text
        }
    }
    return ""
}

// is_defer_free checks if node is a defer free statement
is_defer_free :: proc(node: ^ASTNode) -> bool {
    if node.node_type != "defer_statement" {
        return false
    }
    
    // Check if defer calls free/delete
    for &child in node.children {
        if child.node_type == "call_expression" {
            for &grandchild in child.children {
                if grandchild.node_type == "identifier" {
                    if grandchild.text == "free" || grandchild.text == "delete" {
                        return true
                    }
                }
            }
        }
    }
    
    return false
}

// extract_freed_var_name extracts the variable name from defer free
extract_freed_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "call_expression" {
            for &grandchild in child.children {
                if grandchild.node_type == "identifier" {
                    return grandchild.text
                }
            }
        }
    }
    return ""
}

// changes_context_allocator checks if node reassigns context.allocator
changes_context_allocator :: proc(node: ^ASTNode) -> bool {
    if node.node_type != "assignment_statement" {
        return false
    }
    
    // Check if LHS is context.allocator
    for &child in node.children {
        if child.node_type == "field_expression" {
            for &grandchild in child.children {
                if grandchild.node_type == "identifier" && grandchild.text == "context" {
                    for &greatgrandchild in child.children {
                        if greatgrandchild.node_type == "field_identifier" && 
                           greatgrandchild.text == "allocator" {
                            return true
                        }
                    }
                }
            }
        }
    }
    
    return false
}

// is_return_statement checks if node is a return statement
is_return_statement :: proc(node: ^ASTNode) -> bool {
    return node.node_type == "return_statement"
}

// extract_returned_vars recursively finds all identifiers in a return statement
extract_returned_vars :: proc(node: ^ASTNode, result: ^map[string]bool) {
    // Recursively find all identifiers inside a return statement
    for &child in node.children {
        if child.node_type == "identifier" && child.text != "" {
            result[child.text] = true
        }
        extract_returned_vars(&child, result)
    }
}

// has_manual_cleanup detects explicit cleanup patterns
has_manual_cleanup :: proc(node: ^ASTNode, block: ^ASTNode) -> bool {
    var_name := extract_lhs_name(node)
    if var_name == "" || var_name == "_" {
        return false
    }
    
    // Look for manual free/delete patterns in the same block
    for &child in block.children {
        if child.node_type == "expression_statement" {
            if is_free_call(&child, var_name) {
                return true
            }
        }
        if child.node_type == "if_statement" {
            // Check if condition involves the variable
            if contains_identifier(&child, var_name) {
                // Look for free in the if body
                for &grandchild in child.children {
                    if is_free_call(&grandchild, var_name) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

// is_free_call checks if a node contains a free/delete call for a specific variable
is_free_call :: proc(node: ^ASTNode, var_name: string) -> bool {
    if node.node_type != "call_expression" {
        return false
    }
    
    for &child in node.children {
        if child.node_type == "identifier" {
            if child.text == "free" || child.text == "delete" {
                // Check if var_name is in the arguments
                for &arg in node.children {
                    if arg.node_type == "identifier" && arg.text == var_name {
                        return true
                    }
                }
            }
        }
    }
    return false
}

// contains_identifier checks if a node contains a specific identifier
contains_identifier :: proc(node: ^ASTNode, target: string) -> bool {
    if node.node_type == "identifier" && node.text == target {
        return true
    }
    
    for &child in node.children {
        if contains_identifier(&child, target) {
            return true
        }
    }
    return false
}

// extract_returned_var_name extracts the variable name from return statement (legacy)
extract_returned_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "identifier" {
            return child.text
        }
    }
    return ""
}

// is_global_assignment detects global variable initializations
is_global_assignment :: proc(node: ^ASTNode) -> bool {
    // Global variables typically have simple LHS (just an identifier)
    // and often have specific naming patterns
    
    lhs_complexity := 0
    for &child in node.children {
        if child.node_type == "selector_expression" || 
           child.node_type == "index_expression" {
            lhs_complexity += 1
        }
    }
    
    // If LHS is complex, it's not a simple global assignment
    if lhs_complexity > 0 {
        return false
    }
    
    // Check for common global variable naming patterns
    for &child in node.children {
        if child.node_type == "identifier" {
            // Check for stdio globals
            if child.text == "stdin" || child.text == "stdout" || child.text == "stderr" {
                return true
            }
            // Check for other common global patterns
            if strings.has_prefix(child.text, "default_") ||
               strings.has_prefix(child.text, "global_") ||
               strings.has_suffix(child.text, "_global") {
                return true
            }
        }
    }
    
    return false
}

// uses_non_default_allocator checks if allocation uses non-default allocator
uses_non_default_allocator :: proc(call_node: ^ASTNode, file_path: string) -> bool {
    // Enhanced allocator detection: check ALL parameters, not just last one
    // Handle slice allocations with allocator parameters
    // Detect chan.create_buffered with allocator
    
    // Read source file to get actual text
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return false
    }
    content_str := string(content)
    
    // Extract the line containing the allocation
    lines := strings.split(content_str, "\n")
    if call_node.start_line - 1 < len(lines) {
        line_content := lines[call_node.start_line - 1]
        
        // Check for allocator patterns in the entire line
        // This catches allocator in any parameter position
        if strings.contains(line_content, "temp_allocator") ||
           strings.contains(line_content, "context.allocator") ||
           strings.contains(line_content, "allocator") ||
           strings.contains(line_content, "custom_allocator") {
            return true
        }
        
        // Special handling for chan.create_buffered with allocator
        if strings.contains(line_content, "chan.create_buffered") {
            return true
        }
        
        // Handle slice allocations with allocator parameters
        // Pattern: make([dynamic]Element, 1024, 1024, allocator)
        if strings.contains(line_content, "make(") {
            // Simple heuristic: if line contains "make(" and has multiple commas, likely has allocator
            // Count commas in the entire line
            comma_count := strings.count(line_content, ",")
            // Also check for allocator keywords
            has_allocator := strings.contains(line_content, "allocator")
            
            if comma_count >= 3 || has_allocator {
                // Multiple parameters or explicit allocator - likely includes allocator
                return true
            }
        }
    }
    return false
}

// c001Message returns the rule message
c001Message :: proc() -> string {
    return "Allocation without matching defer free in same scope"
}

// c001FixHint returns the fix hint
c001FixHint :: proc() -> string {
    return "Add defer free() immediately after allocation"
}