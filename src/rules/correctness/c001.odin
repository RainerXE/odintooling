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
    
    // Log that we're analyzing for C001
    // In production, this would use proper logging
    // log.infof("Analyzing file for C001 violations")
    
    // Walk through all declarations in the file
    for decl in ast.file.decls {
        // Check the type of declaration using proper Odin switch syntax
        switch t in decl.expr {
            case ^ast.Value_Decl:
                v := t
                // Check for allocations in value declarations
                // Example: data := new(MyData)
                for expr in v.values {
                    check_expression_for_allocation(expr, &diagnostics)
                }
            
            case ^ast.Assign_Expr:
                a := t
                // Check for allocations in assignments
                // Example: data = new(MyData)
                check_expression_for_allocation(a.rhs, &diagnostics)
            
            case ^ast.If_Expr:
                i := t
                // Check allocations in if expressions
                check_expression_for_allocation(i.cond, &diagnostics)
                check_expression_for_allocation(i.then, &diagnostics)
                if i.else_expr != nil {
                    check_expression_for_allocation(i.else_expr, &diagnostics)
                }
            
            case ^ast.For_Expr:
                f := t
                // Check allocations in for loops
                if f.init != nil {
                    check_expression_for_allocation(f.init, &diagnostics)
                }
                if f.cond != nil {
                    check_expression_for_allocation(f.cond, &diagnostics)
                }
                if f.post != nil {
                    check_expression_for_allocation(f.post, &diagnostics)
                }
                check_expression_for_allocation(f.body, &diagnostics)
            
            case ^ast.Switch_Expr:
                s := t
                // Check allocations in switch expressions
                check_expression_for_allocation(s.expr, &diagnostics)
                for case_expr in s.cases {
                    check_expression_for_allocation(case_expr, &diagnostics)
                }
            
            case ^ast.Return_Expr:
                r := t
                // Check allocations in return statements
                if r.expr != nil {
                    check_expression_for_allocation(r.expr, &diagnostics)
                }
            
            case ^ast.Defer_Expr:
                d := t
                // Check allocations in defer statements
                // These are actually OK since they're in defer context
                // But we still check nested expressions
                check_expression_for_allocation(d.expr, &diagnostics)
            
            // Add more declaration types as needed
        }
    }
    
    // Log results
    // log.infof("Found %d C001 violations", len(diagnostics))
    
    return diagnostics
}

// Check an expression for allocation patterns
check_expression_for_allocation :: proc(expr: ^ast.Expr, diagnostics: ^[dynamic]Diagnostic) {
    // This function recursively walks the AST to find allocation calls
    // that are not properly handled with defer free
    
    switch e := expr in {
        case ^ast.Call_Expr: {
            // Check for allocation function calls
            if is_allocation_call(e) {
                // For now, we assume it's not in defer context
                // TODO: Implement proper defer context detection
                add_allocation_diagnostic(expr, diagnostics)
            }
        }
        
        // Recursively check nested expressions
        case ^ast.Paren_Expr: {
            check_expression_for_allocation(e.expr, diagnostics)
        }
        
        case ^ast.Unary_Expr: {
            // Check unary expressions (e.g., &pointer)
            check_expression_for_allocation(e.expr, diagnostics)
        }
        
        case ^ast.Binary_Expr: {
            // Check binary expressions (e.g., a + b)
            check_expression_for_allocation(e.left, diagnostics)
            check_expression_for_allocation(e.right, diagnostics)
        }
        
        case ^ast.Index_Expr: {
            // Check index expressions (e.g., array[i])
            check_expression_for_allocation(e.expr, diagnostics)
            check_expression_for_allocation(e.index, diagnostics)
        }
        
        case ^ast.Selector_Expr: {
            // Check selector expressions (e.g., obj.field)
            check_expression_for_allocation(e.expr, diagnostics)
        }
        
        case ^ast.Slice_Expr: {
            // Check slice expressions (e.g., array[0..1])
            check_expression_for_allocation(e.expr, diagnostics)
            if e.low != nil {
                check_expression_for_allocation(e.low, diagnostics)
            }
            if e.high != nil {
                check_expression_for_allocation(e.high, diagnostics)
            }
        }
        
        case ^ast.Call_Expr: {
            // Already handled above, but included for completeness
            check_expression_for_allocation(e.expr, diagnostics)
            for arg in e.args {
                check_expression_for_allocation(arg, diagnostics)
            }
        }
        
        // Add more expression types as needed
    }
}

// Check if a call expression is an allocation function
is_allocation_call :: proc(call: ^ast.Call_Expr) -> bool {
    // Check for common allocation functions
    // We look for calls that allocate memory which should be freed
    
    if call.args.len == 0 {
        return false  // Allocation calls typically have arguments
    }
    
    switch call.expr in {
        case ^ast.Ident: {
            // Check for built-in allocation functions
            switch call.expr.token.text {
                case "new": {
                    // new(Type) - allocates memory
                    return true
                }
                case "make": {
                    // make(Type, ...) - may allocate memory
                    return true
                }
                case "alloc": {
                    // alloc(size) - direct allocation
                    return true
                }
                case "malloc": {
                    // malloc(size) - C-style allocation
                    return true
                }
                case "calloc": {
                    // calloc(count, size) - C-style allocation
                    return true
                }
            }
        }
        case ^ast.Selector_Expr: {
            // Check for package-qualified allocations
            // e.g., mem.alloc(), mypkg.new()
            switch call.expr.token.text {
                case "alloc", "new", "make": {
                    return true
                }
            }
        }
    }
    return false
}

// Check if an expression is within a defer context
is_in_defer_context :: proc(expr: ^ast.Expr) -> bool {
    // TODO: Implement proper defer context detection
    // This requires walking up the AST to check for defer statements
    // 
    // Current approach: We're being conservative and assuming
    // allocations are NOT in defer context. This means we might
    // report some false positives, but we won't miss any real issues.
    //
    // Future implementation will:
    // 1. Walk up the AST to find parent nodes
    // 2. Check if we're directly inside a defer statement
    // 3. Handle nested defer contexts properly
    // 4. Track defer statements at the function level
    
    return false  // Conservative approach: assume not in defer
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