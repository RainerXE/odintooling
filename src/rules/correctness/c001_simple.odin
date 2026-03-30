package rules

import "core:odin/ast"
import "src:server/types"

// C001: Allocation without defer free
// 
// This rule detects allocations that are not properly freed with defer.
// It helps prevent memory leaks in Odin programs.

// Analyze AST for C001 violations
analyze_c001 :: proc(ast: ^ast.File) -> [dynamic]Diagnostic {
    var diagnostics: [dynamic]Diagnostic
    
    // Walk through all declarations in the file
    for decl in ast.file.decls {
        // Check the type of declaration
        switch decl.expr in {
            case ^ast.Value_Decl:
                v := decl.expr
                // Check for allocations in value declarations
                // Example: data := new(MyData)
                for expr in v.values {
                    check_for_allocation(expr, &diagnostics)
                }
            
            case ^ast.Assign_Expr:
                a := decl.expr
                // Check for allocations in assignments
                // Example: data = new(MyData)
                check_for_allocation(a.rhs, &diagnostics)
            
            // Add more declaration types as needed
        }
    }
    
    return diagnostics
}

// Check if an expression contains an allocation
check_for_allocation :: proc(expr: ^ast.Expr, diagnostics: ^[dynamic]Diagnostic) {
    switch e in expr {
        case ^ast.Call_Expr:
            // Check for allocation function calls
            if is_allocation_call(e) {
                // For now, we assume it's not in defer context
                // TODO: Implement proper defer context detection
                add_allocation_diagnostic(expr, diagnostics)
            }
        
        // Recursively check nested expressions
        case ^ast.Paren_Expr:
            check_for_allocation(e.expr, diagnostics)
        
        // Add more expression types as needed
    }
}

// Check if a call expression is an allocation function
is_allocation_call :: proc(call: ^ast.Call_Expr) -> bool {
    // Check for common allocation functions
    if call.args.len == 0 {
        return false  // Allocation calls typically have arguments
    }
    
    switch call.expr in {
        case ^ast.Ident:
            // Check for built-in allocation functions
            switch call.expr.token.text {
                case "new": return true  // new(Type)
                case "make": return true  // make(Type, ...)
                case "alloc": return true  // alloc(size)
                case "malloc": return true // malloc(size)
                case "calloc": return true // calloc(count, size)
            }
        
        case ^ast.Selector_Expr:
            // Check for package-qualified allocations
            // e.g., mem.alloc(), mypkg.new()
            switch call.expr.token.text {
                case "alloc", "new", "make": return true
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
        message = "Allocation without corresponding defer free detected",
    }
    
    append(diagnostics, diag)
}