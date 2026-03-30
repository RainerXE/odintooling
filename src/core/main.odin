package core

import "core:fmt"
import "core:os"
import "core:strings"
// LSP integration is handled by OLS (Odin Language Server)
// C002 rule is now in the same package

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

// Rule represents a linting rule
Rule :: struct {
    id: string,
    tier: string,
    matcher: proc(file_path: string, node: ^ASTNode) -> Diagnostic,
    message: proc() -> string,
    fix_hint: proc() -> string,
}

// RuleRegistry manages all linting rules
RuleRegistry :: struct {
    rules: map[string] Rule,
}

// initRuleRegistry creates a new rule registry
initRuleRegistry :: proc() -> RuleRegistry {
    return RuleRegistry{
        rules = make(map[string] Rule),
    }
}

// registerRule adds a rule to the registry
registerRule :: proc(registry: ^RuleRegistry, rule:  Rule) {
    registry.rules[rule.id] = rule
}

// getRule gets a rule by ID
getRule :: proc(registry: RuleRegistry, id: string) -> ( Rule, bool) {
    rule, ok := registry.rules[id]
    if !ok {
        return  Rule{}, false
    }
    return rule, true
}

// emitDiagnostic emits a diagnostic
emitDiagnostic :: proc(diag:  Diagnostic) {
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
stubRule :: proc(file_path: string) -> ( Diagnostic, bool) {
    // Check if file contains "TODO_FIXME" pattern
    // This is a placeholder - actual implementation will use tree-sitter
    
    fmt.println("Checking stub rule for:", file_path)
    
    // Simple file content check for now
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return  Diagnostic{}, false
    }
    defer delete(content)
    
    content_str := string(content)
    if strings.contains(content_str, "TODO_FIXME") {
        return  Diagnostic{
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
    
    return  Diagnostic{}, false
}

// main entry point
main :: proc() {
    fmt.println("Starting odin-lint")
    
    // Parse command line arguments
    args := os.args
    if len(args) < 2 {
        fmt.println("Usage: odin-lint <file> [--lsp|--ast] [--server]")
        fmt.println("  --lsp: Run in LSP mode for editor integration")
        fmt.println("  --lsp --server: Run as standalone LSP server")
        fmt.println("  --ast: Export AST in JSON format")
        os.exit(1)
    }
    
    file_path := args[1]
    
    // Check for special modes
    ast_mode := false
    
    if len(args) > 2 {
        if args[2] == "--ast" {
            ast_mode = true
            fmt.println("Running in AST export mode")
        }
    }
    
    if ast_mode {
        runASTExport(file_path)
        return
    }
    
    fmt.println("Processing file:", file_path)
    
    // Initialize tree-sitter AST parser
    ts_parser, ts_ok := initTreeSitterParser()
    if !ts_ok {
        fmt.println("Failed to initialize tree-sitter parser")
        os.exit(1)
    }
    
    // Parse file to get AST
    ast_root, parse_ok := parseFile(ts_parser, file_path)
    if !parse_ok {
        fmt.println("Failed to parse file:", file_path)
        deinitTreeSitterParser(ts_parser)
        os.exit(1)
    }
    
    // Initialize rule registry
    registry := initRuleRegistry()
    
    // Register rules
    registerRule(&registry, C001Rule())
    registerRule(&registry, C002Rule())
    
    // Apply all rules
    diagnostics_found := false
    // Apply C001 rule with parsed AST
    c001_rule := C001Rule()
    diag := c001_rule.matcher(file_path, &ast_root)
    if diag.message != "" {
        emitDiagnostic(diag)
        diagnostics_found = true
    }
    
    // Apply C002 rule with parsed AST
    c002_rule := C002Rule()
    diag2 := c002_rule.matcher(file_path, &ast_root)
    if diag2.message != "" {
        emitDiagnostic(diag2)
        diagnostics_found = true
    }
    
    // Also run stub rule for now
    stub_diag, stub_found := stubRule(file_path)
    if stub_found {
        emitDiagnostic(stub_diag)
        diagnostics_found = true
    }
    
    if diagnostics_found {
        deinitTreeSitterParser(ts_parser)
        os.exit(1)  // Exit with error code for findings
    }
    
    deinitTreeSitterParser(ts_parser)
    fmt.println("No diagnostics found")
    os.exit(0)
}