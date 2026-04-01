package core

import "core:fmt"
import "core:os"
import "core:strings"

// C001 rule implementation
// C001: Allocation without matching defer free in same scope
// Inspired by: Rust clippy::mem_forget

// C001ScopeContext :: struct for block-level analysis
C001ScopeContext :: struct {
    allocations: [dynamic]AllocationInfo,
    defers:      [dynamic]DeferInfo,
    has_arena:   bool,
    returns_var: map[string]bool,
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
        matcher = c001Matcher,
        message = c001Message,
        fix_hint = c001FixHint,
    }
}

// c001Matcher checks for allocations without defer free
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // Check if this is a block node (tree-sitter uses "block", not "block_statement")
    if node.node_type == "block" {
        // Check block for C001 violations
        diagnostics := check_block_for_c001(node, file_path)
        if len(diagnostics) > 0 {
            return diagnostics[:][0]  // Return first diagnostic found
        }
    }
    
    // Recursively check children for block nodes
    for &child in node.children {
        diag := c001Matcher(file_path, &child)
        if diag.message != "" {
            return diag
        }
    }
    
    return Diagnostic{}
}

// check_block_for_c001 checks a block for C001 violations
check_block_for_c001 :: proc(block: ^ASTNode, file_path: string) -> []Diagnostic {
    ctx := C001ScopeContext{}
    
    // Collect allocations and defers in this block
    for &child in block.children {
        if is_allocation_assignment(&child, file_path) {
            var_name := extract_lhs_name(&child)
            if var_name != "" {
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
            returned_var := extract_returned_var_name(&child)
            if returned_var != "" {
                ctx.returns_var[returned_var] = true
            }
        }
    }
    
    // Skip if context.allocator is reassigned
    if ctx.has_arena {
        return {}
    }
    
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
        
        // Check if allocation uses temp_allocator
        if uses_temp_allocator(alloc) {
            continue
        }
        
        // Fire diagnostic
        append(&diagnostics, Diagnostic{
            file = file_path,
            line = alloc.line,
            column = alloc.col,
            rule_id = "C001",
            tier = "correctness",
            message = "Allocation without matching defer free in same scope",
            fix = "Add defer free() immediately after allocation",
            has_fix = true,
        })
    }
    
    return diagnostics[:]
}

// is_allocation_assignment checks if node is an allocation assignment
is_allocation_assignment :: proc(node: ^ASTNode, file_path: string) -> bool {
    if node.node_type != "assignment_statement" {
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

// extract_returned_var_name extracts the variable name from return statement
extract_returned_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "identifier" {
            return child.text
        }
    }
    return ""
}

// uses_temp_allocator checks if allocation uses temp_allocator
uses_temp_allocator :: proc(alloc: AllocationInfo) -> bool {
    // This would require checking the allocator argument in the call
    // For now, we'll skip this check as it requires more complex analysis
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