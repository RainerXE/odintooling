package core

import "core:fmt"
import "core:os"
import "core:strings"

// Diagnostic represents a linting diagnostic
Diagnostic :: struct {
    file:    string,
    line:    int,
    column:  int,
    rule_id: string,
    tier:    string,
    message: string,
    fix:     string,
    has_fix: bool,
}

// ASTWalker represents the AST walker
ASTWalker :: struct {
    // Placeholder for AST walker implementation
}

// walkAST walks the AST and applies rules
walkAST :: proc(walker: ^ASTWalker, node: rawptr) {
    // Placeholder for AST walking logic
    fmt.println("Walking AST node")
}

// emitDiagnostic emits a diagnostic
emitDiagnostic :: proc(diag: Diagnostic) {
    // Format diagnostic output
    fmt.printf("%s:%d:%d: %s [%s] %s",
               diag.file, diag.line, diag.column,
               diag.rule_id, diag.tier, diag.message)
    
    if diag.has_fix {
        fmt.printf("\nFix: %s", diag.fix)
    }
    
    fmt.println()
}

// stubRule is a stub rule for pipeline validation
stubRule :: proc(file_path: string) -> (Diagnostic, bool) {
    // Check if file contains "TODO_FIXME" pattern
    // This is a placeholder - actual implementation will use tree-sitter
    
    fmt.println("Checking stub rule for:", file_path)
    
    // Simple file content check for now
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return {}, false
    }
    defer delete(content)
    
    content_str := string(content)
    if strings.contains(content_str, "TODO_FIXME") {
        return Diagnostic{
            file = file_path,
            line = 1,
            column = 1,
            rule_id = "STUB001",
            tier = "correctness",
            message = "Found TODO_FIXME procedure",
            fix = "Rename or remove TODO_FIXME procedure",
            has_fix = true,
        }, true
    }
    
    return {}, false
}

// main entry point
main :: proc() {
    fmt.println("Starting odin-lint")
    
    // Parse command line arguments
    args := os.args
    if len(args) < 2 {
        fmt.println("Usage: odin-lint <file>")
        os.exit(1)
    }
    
    file_path := args[1]
    
    fmt.println("Processing file:", file_path)
    
    // Create AST walker
    walker := ASTWalker{}
    
    // Parse file (placeholder - will use tree-sitter)
    // For now, we'll just apply the stub rule
    
    // Apply stub rule
    diag, found := stubRule(file_path)
    if found {
        emitDiagnostic(diag)
        os.exit(1)  // Exit with error code for correctness findings
    }
    
    fmt.println("No diagnostics found")
    os.exit(0)
}