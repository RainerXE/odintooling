package rules

import "core:odin/ast"
import "vendor/ols/src/server/types"

// C001: Allocation without defer free
// 
// This rule detects Odin allocations (new, make) that are not properly
// freed with defer. It helps prevent memory leaks in Odin programs.
//
// Focus: Odin-specific memory management (not C-style allocations)
// Patterns: new(Type), make(Type, ...), mem.alloc(), etc.
// Solution: Add defer free() immediately after allocation
=======

// Analyze AST for C001 violations
analyze_c001 :: proc(ast: ^ast.File) -> [dynamic]Diagnostic {
    var diagnostics: [dynamic]Diagnostic
    
    // Walk through all declarations in the file
    for decl in ast.file.decls {
        // Check the type of declaration
        if value_decl, ok := decl.expr.(^ast.Value_Decl); ok {
            // Check for allocations in value declarations
            // Example: data := new(MyData)
            for expr in value_decl.values {
                check_expression_for_allocation(expr, &diagnostics)
            }
        }
        
        // Check for assignments
        if assign_expr, ok := decl.expr.(^ast.Assign_Expr); ok {
            // Check for allocations in assignments
            // Example: data = new(MyData)
            check_expression_for_allocation(assign_expr.rhs, &diagnostics)
        }
    }
    
    return diagnostics
}

// Check if an expression contains an allocation
check_expression_for_allocation :: proc(expr: ^ast.Expr, diagnostics: ^[dynamic]Diagnostic) {
    // Check if this is a call expression
    if call_expr, ok := expr.(^ast.Call_Expr); ok {
        // Check for allocation function calls
        if is_allocation_call(call_expr) {
            // For now, we assume it's not in defer context
            // TODO: Implement proper defer context detection
            add_allocation_diagnostic(expr, diagnostics)
        }
    }
    
    // Recursively check nested expressions
    if paren_expr, ok := expr.(^ast.Paren_Expr); ok {
        check_expression_for_allocation(paren_expr.expr, diagnostics)
    }
}

// Check if a call expression is an allocation function
is_allocation_call :: proc(call: ^ast.Call_Expr) -> bool {
    // Check for Odin-specific allocation functions
    // Note: We focus only on Odin patterns, not C-style allocations
    
    if call.args.len == 0 {
        return false  // Allocation calls typically have arguments
    }
    
    // Check identifier calls (new, make)
    if ident, ok := call.expr.(^ast.Ident); ok {
        switch ident.token.text {
            case "new": return true   // new(Type) - Odin's primary allocation
            case "make": return true  // make(Type, ...) - for slices, maps, etc.
            // Removed: alloc, malloc, calloc (these are C-style, not typical Odin)
        }
    }
    
    // Check selector expressions (pkg.func)
    // This handles cases like mem.alloc() from core:mem
    if selector, ok := call.expr.(^ast.Selector_Expr); ok {
        switch selector.token.text {
            case "alloc": return true  // mem.alloc() from core:mem
            case "new": return true    // pkg.new()
            case "make": return true   // pkg.make()
        }
    }
    
    return false
}

// Add a diagnostic for allocation without defer
add_allocation_diagnostic :: proc(expr: ^ast.Expr, diagnostics: ^[dynamic]Diagnostic) {
    // Get the position information
    pos := expr.token.pos
    
    diag := Diagnostic{
        range = common.Range{
            start = common.Position{line = pos.line - 1, character = pos.column - 1},
            end = common.Position{line = pos.line - 1, character = pos.column},
        },
        severity = DiagnosticSeverity.Warning,
        code = "C001",
        source = "odin-lint",
        message = "Memory allocation without corresponding defer free detected",
    }
    
    append(diagnostics, diag)
}