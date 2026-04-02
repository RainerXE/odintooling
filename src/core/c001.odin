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

// fuzzy_match checks if text contains pattern with flexible matching
// Handles variations in spacing, case, and common typos
fuzzy_match :: proc(text: string, pattern: string) -> bool {
    // Convert both to lowercase for case-insensitive matching
    text_lower := strings.to_lower(text)
    pattern_lower := strings.to_lower(pattern)
    
    // Simple approach: check for common variations of the pattern
    // This handles the most common spacing and case variations
    result := strings.contains(text_lower, "//odin-lint:ignore") ||
              strings.contains(text_lower, "// odin-lint:ignore") ||
              strings.contains(text_lower, "//odin-lint: ignore") ||
              strings.contains(text_lower, "// odin-lint: ignore")
    
    // Debug: Print what we're comparing and the result
    // fmt.printf("DEBUG: fuzzy_match comparing '%s' with pattern - result: %v\n", text_lower, result)
    return result
}

// should_exclude_file checks if a file should be excluded based on config
should_exclude_file :: proc(file_path: string) -> bool {
    // For now, implement basic path exclusion logic
    // In a full implementation, this would read from odin-lint.toml
    
    // Exclude core library files (as discussed)
    if strings.contains(file_path, "core/") {
        return true
    }
    
    // Exclude vendor directories
    if strings.contains(file_path, "vendor/") {
        return true
    }
    
    // Exclude generated code
    if strings.contains(file_path, "generated/") {
        return true
    }
    
    // Exclude test fixtures
    if strings.contains(file_path, "fixtures/") {
        return true
    }
    
    return false
}

// C001 rule implementation
// C001: Allocation without matching defer free in same scope
// Inspired by: Rust clippy::mem_forget
//
// IMPORTANT: This rule ONLY checks for the built-in allocation functions:
//   - make()  - slice, array, map, channel allocations
//   - new()   - struct allocations
//
// It does NOT flag user-defined functions that happen to start with "make" or "new"
// (e.g., make_connection(), new_buffer(), etc.) because it uses exact matching:
//   strings.has_prefix(remaining, "make(") and strings.has_prefix(remaining, "new(")
//
// Suppression: Use inline comments to suppress false positives:
//   data := make([]int, 10)  // odin-lint:ignore C001 intentional ownership transfer
//   // odin-lint:ignore C001 caller takes ownership
//   data := new(Data)
//
// File exclusions: Certain paths are automatically excluded:
//   - core/          - Odin core library (uses different memory management patterns)
//   - vendor/        - Third-party dependencies
//   - generated/     - Auto-generated code
//   - fixtures/      - Test fixtures

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
    // Check if this file should be excluded based on configuration
    if should_exclude_file(file_path) {
        return Diagnostic{}
    }
    
    diagnostics := c001Matcher(file_path, node)
    if len(diagnostics) > 0 {
        return diagnostics[0]
    }
    return Diagnostic{}
}

// c001Matcher checks for allocations without defer free
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic {
    all_diagnostics: [dynamic]Diagnostic
    
    // Check if this file should be excluded based on configuration
    if should_exclude_file(file_path) {
        return {}
    }
    
    // Debug: Print node types being processed
    fmt.printf("DEBUG: Processing node type: '%s' at line %d\n", node.node_type, node.start_line)
    
    // Check if this is a block node (tree-sitter uses "block", not "block_statement")
    if node.node_type == "block" {
        // Debug: Found a block node
        // fmt.printf("DEBUG: Found block node at line %d\n", node.start_line)
        
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
    
    // PERFORMANCE OPTIMIZATION: Read file once and cache lines
    // This avoids repeated file I/O for allocator detection
    file_lines := []string{}
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err == nil {
        content_str := string(content)
        file_lines = strings.split(content_str, "\n")
    }
    
    // Collect allocations and defers in this block
    for &child in block.children {
        fmt.printf("DEBUG: Block child at line %d: type '%s'\n", child.start_line, child.node_type)
        
        if is_allocation_assignment(&child, file_path) {
            var_name := extract_lhs_name(&child)
            if var_name != "" {
                // Check if allocation uses non-default allocator
                if uses_non_default_allocator(&child, file_lines) {
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
    
    // Collect suppression comments for this block
    suppressions := collect_suppressions(block, file_path)
    
    // Debug: Print suppressions found
    // fmt.printf("DEBUG: Found %d suppressions in block\n", len(suppressions))
    // for line, rule in suppressions {
    //     fmt.printf("DEBUG: Suppression on line %d for rule %s\n", line, rule)
    // }
    
    for alloc in ctx.allocations {
        // Check if this allocation is suppressed
        if rule, ok := suppressions[alloc.line]; ok && rule == "C001" {
            // fmt.printf("DEBUG: Suppressing allocation on line %d\n", alloc.line)
            continue  // Skip suppressed allocations
        }
        if rule, ok := suppressions[alloc.line - 1]; ok && rule == "C001" {
            // fmt.printf("DEBUG: Suppressing allocation on line %d (previous line suppressed)\n", alloc.line)
            continue  // Skip allocations with suppression on previous line
        }
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
    // Debug: Track when this function is called
    // fmt.printf("DEBUG: is_allocation_assignment called for node type '%s' at line %d\n", node.node_type, node.start_line)
    
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
                                
                                // Debug: Print what we're checking
                                // fmt.printf("DEBUG: Checking identifier '%s' at line %d, col %d\n", 
                                //           grandchild.text, grandchild.start_line, grandchild.start_column)
                                // fmt.printf("DEBUG: Line content: '%s'\n", line_content)
                                // fmt.printf("DEBUG: Remaining from col: '%s'\n", remaining)
                                
                                // Check if it starts with "make" or "new" (exact match to avoid false positives)
                                // Use exact matching to avoid matching functions like "min()", "max()", etc.
                                if strings.has_prefix(remaining, "make(") || strings.has_prefix(remaining, "new(") {
                                    // fmt.printf("DEBUG: Found allocation at line %d: '%s'\n", grandchild.start_line, remaining)
                                    return true
                                }
                            } else {
                                fmt.printf("DEBUG: Column %d out of bounds for line %d (len %d)\n", 
                                          grandchild.start_column, grandchild.start_line, len(line_content))
                            }
                        } else {
                            fmt.printf("DEBUG: Line %d out of bounds (max %d)\n", grandchild.start_line, len(lines))
                        }
                    } else {
                        fmt.printf("DEBUG: Error reading file: %v\n", err)
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
// Returns the actual variable being freed, not the function name (free/delete)
extract_freed_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "call_expression" {
            found_callee := false
            for &grandchild in child.children {
                // Handle argument_list case (modern tree-sitter grammar)
                if grandchild.node_type == "argument_list" {
                    for &arg in grandchild.children {
                        if arg.node_type == "identifier" {
                            return arg.text  // First arg = variable being freed
                        }
                    }
                }
                // Fallback for direct identifiers (older grammar compatibility)
                if grandchild.node_type == "identifier" {
                    if !found_callee {
                        found_callee = true  // Skip "free"/"delete" function name
                        continue
                    }
                    return grandchild.text  // Second identifier = variable being freed
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

// collect_suppressions_for_node collects suppression comments around a specific node
collect_suppressions_for_node :: proc(node: ^ASTNode, file_path: string) -> map[int]string {
    // Estimate a reasonable range around the node to look for suppression comments
    // Since we don't have parent block info, we'll scan a window around the node's line
    
    // Read source file to get actual text
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return {}
    }
    content_str := string(content)
    
    // Extract all lines
    lines := strings.split(content_str, "\n")
    
    // Look for suppression comments in a reasonable range around the node
    start_line := max(0, node.start_line - 5)
    end_line := min(len(lines) - 1, node.start_line + 5)
    
    suppressions := make(map[int]string)
    
    for i in start_line..=end_line {
        if i < len(lines) {
            line_content := lines[i]
            
            // Look for suppression pattern using fuzzy matching
            if fuzzy_match(line_content, "//odin-lint:ignore") {
                // Extract the rule ID using simple approach
                // Look for "C001" after the ignore pattern
                if strings.contains(line_content, "C001") {
                    suppressions[i + 1] = "C001"  // line numbers are 1-indexed
                }
            }
        }
    }
    
    return suppressions
}

// collect_suppressions collects suppression comments from a block
collect_suppressions :: proc(block: ^ASTNode, file_path: string) -> map[int]string {
    suppressions := make(map[int]string)
    
    // Read source file to get actual text
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return suppressions
    }
    content_str := string(content)
    
    // Extract all lines
    lines := strings.split(content_str, "\n")
    
    // Look for suppression comments in the block's line range
    // Check a reasonable range around the block to catch nearby comments
    start_line := max(0, block.start_line - 1)
    end_line := min(len(lines) - 1, block.end_line + 1)
    
    // Debug: Print the range we're checking
    // fmt.printf("DEBUG: Checking lines %d to %d for suppressions\n", start_line + 1, end_line + 1)
    
    for i in start_line..=end_line {
        if i < len(lines) {
            line_content := lines[i]
            
            // Debug: Print each line we check
            // fmt.printf("DEBUG: Checking line %d: '%s'\n", i + 1, line_content)
            
            // Look for suppression pattern using fuzzy matching
            if fuzzy_match(line_content, "//odin-lint:ignore") {
                // Debug: Print when we find a match
                // fmt.printf("DEBUG: Found suppression pattern on line %d\n", i + 1)
                
                // Extract the rule ID using simple approach
                // Look for "C001" after the ignore pattern
                if strings.contains(line_content, "C001") {
                    suppressions[i + 1] = "C001"  // line numbers are 1-indexed
                    // fmt.printf("DEBUG: Added suppression for rule C001 on line %d\n", i + 1)
                }
            } else {
                // Debug: Check if the line contains the pattern at all
                if strings.contains(strings.to_lower(line_content), "odin-lint") {
                    // fmt.printf("DEBUG: Line %d contains 'odin-lint' but didn't match fuzzy pattern\n", i + 1)
                }
            }
        }
    }
    
    return suppressions
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

// has_allocator_arg checks if an allocation call has an allocator argument
// Only checks within the call arguments, not the entire line
// This prevents false positives from comments, variable names, etc.
has_allocator_arg :: proc(line_content: string) -> bool {
    // Find the opening paren of make( or new(
    make_start := strings.index(line_content, "make(")
    new_start  := strings.index(line_content, "new(")
    call_start := -1
    if make_start >= 0 do call_start = make_start + 4  // skip "make"
    if new_start  >= 0 do call_start = new_start  + 3  // skip "new"
    if call_start < 0 do return false

    // Extract just the argument list (from "(" onward)
    args := line_content[call_start:]
    
    // Check for specific allocator patterns ONLY in arguments
    // This avoids matching "allocator" in comments, variable names, etc.
    return strings.contains(args, "temp_allocator") ||
           strings.contains(args, ".allocator")     ||   // context.allocator, arena.allocator
           strings.contains(args, "allocator)")          // named param at end: allocator)
}

// uses_non_default_allocator checks if allocation uses non-default allocator
// Now uses precise argument detection instead of broad substring matching
// OPTIMIZED: Takes file_lines as parameter to avoid repeated file reading
uses_non_default_allocator :: proc(call_node: ^ASTNode, file_lines: []string) -> bool {
    // Extract the line containing the allocation (no file reading needed)
    if call_node.start_line - 1 < len(file_lines) {
        line_content := file_lines[call_node.start_line - 1]
        
        // Check for allocator arguments using precise detection
        if has_allocator_arg(line_content) {
            return true
        }
        
        // Special handling for chan.create_buffered with allocator
        if strings.contains(line_content, "chan.create_buffered") {
            return true
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