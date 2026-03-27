package core

import "core:fmt"
import "core:os"
import "core:strings"
import "../rules/correctness"

// Use types from correctness package

// RuleRegistry manages all linting rules
RuleRegistry :: struct {
    rules: map[string]correctness.Rule,
}

// initRuleRegistry creates a new rule registry
initRuleRegistry :: proc() -> RuleRegistry {
    return RuleRegistry{
        rules = make(map[string]correctness.Rule),
    }
}

// registerRule adds a rule to the registry
registerRule :: proc(registry: ^RuleRegistry, rule: correctness.Rule) {
    registry.rules[rule.id] = rule
}

// getRule gets a rule by ID
getRule :: proc(registry: RuleRegistry, id: string) -> (correctness.Rule, bool) {
    rule, ok := registry.rules[id]
    if !ok {
        return correctness.Rule{}, false
    }
    return rule, true
}

// emitDiagnostic emits a diagnostic
emitDiagnostic :: proc(diag: correctness.Diagnostic) {
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
stubRule :: proc(file_path: string) -> (correctness.Diagnostic, bool) {
    // Check if file contains "TODO_FIXME" pattern
    // This is a placeholder - actual implementation will use tree-sitter
    
    fmt.println("Checking stub rule for:", file_path)
    
    // Simple file content check for now
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return correctness.Diagnostic{}, false
    }
    defer delete(content)
    
    content_str := string(content)
    if strings.contains(content_str, "TODO_FIXME") {
        return correctness.Diagnostic{
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
    
    return correctness.Diagnostic{}, false
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
    
    // Initialize rule registry
    registry := initRuleRegistry()
    
    // Register rules
    registerRule(&registry, correctness.C001Rule())
    
    // Apply all rules
    diagnostics_found := false
    // Apply C001 rule
    c001_rule := correctness.C001Rule()
    diag := c001_rule.matcher(file_path, nil)
    if diag.message != "" {
        emitDiagnostic(diag)
        diagnostics_found = true
    }
    
    // Also run stub rule for now
    stub_diag, stub_found := stubRule(file_path)
    if stub_found {
        emitDiagnostic(stub_diag)
        diagnostics_found = true
    }
    
    if diagnostics_found {
        os.exit(1)  // Exit with error code for findings
    }
    
    fmt.println("No diagnostics found")
    os.exit(0)
}