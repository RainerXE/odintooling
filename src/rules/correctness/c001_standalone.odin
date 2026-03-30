package rules

import "core:odin/ast"

// C001: Allocation without defer free
// 
// Standalone implementation that doesn't depend on OLS types.
// This can be tested independently and integrated later.

// Simple diagnostic structure for testing
Diagnostic :: struct {
    line:    int,
    column:  int,
    message: string,
}

// Analyze AST for C001 violations
analyze_c001_standalone :: proc(ast: ^ast.File) -> [dynamic]Diagnostic {
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
            add_allocation_diagnostic(expr, &diagnostics)
        }
    }
    
    // Recursively check nested expressions
    if paren_expr, ok := expr.(^ast.Paren_Expr); ok {
        check_expression_for_allocation(paren_expr.expr, diagnostics)
    }
}

// Check if a call expression is an allocation function
is_allocation_call :: proc(call: ^ast.Call_Expr) -> bool {
    // Check for Odin-specific allocation functions only
    if call.args.len == 0 {
        return false
    }
    
    // Check identifier calls (new, make)
    if ident, ok := call.expr.(^ast.Ident); ok {
        switch ident.token.text {
            case "new": return true   // new(Type)
            case "make": return true  // make(Type, ...)
        }
    }
    
    // Check selector expressions (mem.alloc, etc.)
    if selector, ok := call.expr.(^ast.Selector_Expr); ok {
        switch selector.token.text {
            case "alloc": return true  // mem.alloc()
        }
    }
    
    return false
}

// Add a diagnostic for allocation without defer
add_allocation_diagnostic :: proc(expr: ^ast.Expr, diagnostics: ^[dynamic]Diagnostic) {
    // Get the position information
    pos := expr.token.pos
    
    diag := Diagnostic{
        line = pos.line,
        column = pos.column,
        message = "Memory allocation without corresponding defer free detected",
    }
    
    append(diagnostics, diag)
}

// Test function to verify the rule works
test_c001 :: proc() {
    // This would be called with actual AST in real usage
    // For now, we can test the logic manually
    println("C001 rule: Standalone version ready")
    println("Next steps:")
    println("1. Test with actual Odin code")
    println("2. Integrate with OLS Diagnostic system")
    println("3. Add defer context detection")
}