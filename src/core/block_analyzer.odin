package core

import "core:fmt"
import "core:os"
import "core:strings"
import "core:runtime"

// BlockAnalyzer provides scope-aware analysis of Odin code
// This is the foundation for all linting rules
BlockAnalyzer :: struct {
    // Scope tracking
    scope_stack: [dynamic]Scope,
    current_scope: ^Scope,
    
    // Analysis results
    diagnostics: [dynamic]Diagnostic,
    
    // Configuration
    check_brace_matching: bool = true,  // C0000: Mismatched braces
}

// Scope represents a code block with its own variable and analysis context
Scope :: struct {
    node: ^ASTNode,           // The AST node for this scope
    parent: ^Scope,           // Parent scope (enclosing block)
    depth: int,               // Nesting depth
    start_line: int,          // Line where scope starts
    start_col: int,           // Column where scope starts
    end_line: int,             // Line where scope ends
    end_col: int,             // Column where scope ends
    
    // Variables declared in this scope
    variables: map[string]VariableInfo,
    
    // Allocations in this scope
    allocations: [dynamic]Allocation,
    
    // Defer statements in this scope
    defers: [dynamic]DeferStatement,
    
    // Block type
    block_type: BlockType,
}

// BlockType categorizes different types of blocks
BlockType :: enum {
    UNKNOWN,
    PROCEDURE,
    IF,
    FOR,
    WHILE,
    SWITCH,
    CASE,
    WHEN,
    STRUCT,
    INTERFACE,
    ENUM,
    MATCH,
    BLOCK,  // Generic {}
}

// VariableInfo tracks variable declarations and usage
VariableInfo :: struct {
    name: string,
    declaration: ^ASTNode,
    line: int,
    col: int,
    type: string,
    is_used: bool,
    is_freed: bool,  // For memory safety
}

// Allocation tracks memory allocations that need cleanup
Allocation :: struct {
    node: ^ASTNode,
    variable: string,
    line: int,
    col: int,
    function: string,  // "make", "new", "malloc", etc.
    is_freed: bool,
}

// DeferStatement tracks defer calls for cleanup
DeferStatement :: struct {
    node: ^ASTNode,
    line: int,
    col: int,
    function: string,  // "free", "delete", etc.
    target: string,     // Variable being freed
}

// initBlockAnalyzer creates a new block analyzer
initBlockAnalyzer :: proc() -> BlockAnalyzer {
    return BlockAnalyzer{
        scope_stack = make([dynamic]Scope, 0),
        diagnostics = make([dynamic]Diagnostic, 0),
    }
}

// pushScope pushes a new scope onto the stack
pushScope :: proc(analyzer: ^BlockAnalyzer, node: ^ASTNode, block_type: BlockType) {
    scope := Scope{
        node = node,
        parent = analyzer.current_scope,
        depth = len(analyzer.scope_stack),
        start_line = node.start_line,
        start_col = node.start_column,
        end_line = node.end_line,
        end_col = node.end_column,
        block_type = block_type,
        variables = make(map[string]VariableInfo),
        allocations = make([dynamic]Allocation, 0),
        defers = make([dynamic]DeferStatement, 0),
    }
    
    runtime.append_elem(&analyzer.scope_stack, scope)
    analyzer.current_scope = &analyzer.scope_stack[len(analyzer.scope_stack) - 1]
}

// popScope pops the current scope and validates it
popScope :: proc(analyzer: ^BlockAnalyzer) -> (^Scope, []Diagnostic) {
    if len(analyzer.scope_stack) == 0 {
        return nil, []Diagnostic{}
    }
    
    scope := analyzer.current_scope
    analyzer.scope_stack = analyzer.scope_stack[0..<len(analyzer.scope_stack)-1]
    
    if len(analyzer.scope_stack) > 0 {
        analyzer.current_scope = &analyzer.scope_stack[len(analyzer.scope_stack) - 1]
    } else {
        analyzer.current_scope = nil
    }
    
    // Validate scope before returning
    diagnostics := validateScope(scope)
    
    return scope, diagnostics
}

// validateScope checks for issues in a scope
validateScope :: proc(scope: ^Scope) -> []Diagnostic {
    diagnostics := make([dynamic]Diagnostic, 0)
    
    // Check for unmatched allocations (C001)
    for &alloc in scope.allocations {
        if !alloc.is_freed {
            runtime.append_elem(&diagnostics, Diagnostic{
                file = "",  // Will be set by caller
                line = alloc.line,
                column = alloc.col,
                rule_id = "C001",
                tier = "correctness",
                message = "Allocation without matching defer free in same scope",
                fix = "Add defer free() for allocated resource",
                has_fix = true,
            })
        }
    }
    
    // Check for suspicious defer patterns (C002)
    for &defer in scope.defers {
        if isSuspiciousDefer(&defer) {
            runtime.append_elem(&diagnostics, Diagnostic{
                file = "",  // Will be set by caller
                line = defer.line,
                column = defer.col,
                rule_id = "C002",
                tier = "correctness",
                message = "Defer free on wrong pointer - does not match allocation",
                fix = "Ensure defer free uses the same pointer as allocation",
                has_fix = true,
            })
        }
    }
    
    return diagnostics
}

// isSuspiciousDefer checks if defer might be using wrong pointer
isSuspiciousDefer :: proc(defer: ^DeferStatement) -> bool {
    // Pattern 1: Reassignment before free
    if strings.contains(defer.node.text, "=") {
        return true
    }
    
    // Pattern 2: Complex expressions
    if strings.contains(defer.node.text, "+)") || 
       strings.contains(defer.node.text, "-)") ||
       strings.contains(defer.node.text, "*)") {
        return true
    }
    
    // Pattern 3: Type conversions
    if strings.contains(defer.node.text, "cast") {
        return true
    }
    
    return false
}

// trackAllocation records an allocation in current scope
trackAllocation :: proc(analyzer: ^BlockAnalyzer, alloc: Allocation) {
    if analyzer.current_scope != nil {
        runtime.append_elem(&analyzer.current_scope.allocations, alloc)
    }
}

// trackDefer records a defer statement in current scope
trackDefer :: proc(analyzer: ^BlockAnalyzer, defer: DeferStatement) {
    if analyzer.current_scope != nil {
        runtime.append_elem(&analyzer.current_scope.defers, defer)
    }
}

// trackVariable records a variable declaration
trackVariable :: proc(analyzer: ^BlockAnalyzer, var_info: VariableInfo) {
    if analyzer.current_scope != nil {
        analyzer.current_scope.variables[var_info.name] = var_info
    }
}

// getCurrentScope returns the current scope
getCurrentScope :: proc(analyzer: ^BlockAnalyzer) -> ^Scope {
    return analyzer.current_scope
}

// getScopeDepth returns current nesting depth
getScopeDepth :: proc(analyzer: ^BlockAnalyzer) -> int {
    return len(analyzer.scope_stack)
}

// getDiagnostics returns all collected diagnostics
getDiagnostics :: proc(analyzer: ^BlockAnalyzer) -> []Diagnostic {
    return analyzer.diagnostics
}

// addDiagnostic adds a diagnostic to the analyzer
addDiagnostic :: proc(analyzer: ^BlockAnalyzer, diag: Diagnostic) {
    runtime.append_elem(&analyzer.diagnostics, diag)
}

// clearDiagnostics clears all diagnostics
clearDiagnostics :: proc(analyzer: ^BlockAnalyzer) {
    analyzer.diagnostics = make([dynamic]Diagnostic, 0)
}