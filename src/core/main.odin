package core

import "core:fmt"
import "core:os"
import "core:strings"
// LSP integration is handled by OLS (Odin Language Server)
// C002 rule is now in the same package

// DiagnosticType represents the category of a diagnostic
DiagnosticType :: enum {
    NONE,           // No issues found
    VIOLATION,      // Normal rule violation
    CONTEXTUAL,     // Violation with special context (performance, etc.)
    INTERNAL_ERROR, // Linter internal failure (parse error, file error, etc.)
    INFO,           // Informational message
}

// RuleCategory represents the category of a linting rule (Clippy-inspired)
RuleCategory :: enum {
    CORRECTNESS,   // Bug prevention and memory safety
    STYLE,         // Code style and idiomatic Odin
    COMPLEXITY,    // Code complexity metrics
    PERFORMANCE,   // Performance-related issues
    PEDANTIC,      // Strict/nitpicky checks
    SUSPICIOUS,    // Potentially problematic patterns
}

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
    diag_type: DiagnosticType,
}

// Rule represents a linting rule
Rule :: struct {
    id: string,
    tier: string,
    category: RuleCategory,  // Clippy-inspired categorization
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

// emitDiagnostic emits a diagnostic with appropriate formatting based on type
emitDiagnostic :: proc(diag:  Diagnostic) {
    // Format diagnostic output based on type
    switch diag.diag_type {
        case .INTERNAL_ERROR:
            fmt.printf("🟣 %s:%d:%d: INTERNAL ERROR - %s",
                       diag.file, diag.line, diag.column, diag.message)
        case .CONTEXTUAL:
            fmt.printf("🟡 %s:%d:%d: %s [%s] %s",
                       diag.file, diag.line, diag.column,
                       diag.rule_id, diag.tier, diag.message)
        case .INFO:
            fmt.printf("🔵 %s:%d:%d: INFO - %s",
                       diag.file, diag.line, diag.column, diag.message)
        case .VIOLATION, .NONE:  // NONE shouldn't normally be emitted
            fmt.printf("🔴 %s:%d:%d: %s [%s] %s",
                       diag.file, diag.line, diag.column,
                       diag.rule_id, diag.tier, diag.message)
    }
    
    if diag.has_fix {
        fmt.printf("\nFix: %s", diag.fix)
    }
    
    fmt.println()
}

// dedupDiagnostics removes duplicate diagnostics
// Key: (file, line, column, rule_id) - same violation at same location
dedupDiagnostics :: proc(diags: []Diagnostic) -> []Diagnostic {
    seen := make(map[string]bool)
    result: [dynamic]Diagnostic
    
    for d in diags {
        // Create unique key for this diagnostic
        key := fmt.tprintf("%s:%d:%d:%s", d.file, d.line, d.column, d.rule_id)
        
        // Only add if we haven't seen this exact violation before
        if key not_in seen {
            seen[key] = true
            append(&result, d)
        }
    }
    
    return result[:]
}

// createInternalError creates an internal error diagnostic
createInternalError :: proc(file_path: string, line: int, column: int, error_msg: string) -> Diagnostic {
    return Diagnostic{
        file = file_path,
        line = line,
        column = column,
        rule_id = "INTERNAL",
        tier = "error",
        message = error_msg,
        fix = "This is a linter internal error - please report to developers",
        has_fix = false,
        diag_type = DiagnosticType.INTERNAL_ERROR,
    }
}

// stubRule is a stub rule for pipeline validation
stubRule :: proc(file_path: string) -> (Diagnostic, bool) {
    // Check if file contains "TODO_FIXME" pattern
    // This is a placeholder - actual implementation will use tree-sitter
    
    when ODIN_DEBUG { fmt.println("Checking stub rule for:", file_path) }
    
    // Simple file content check for now
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return Diagnostic{}, false
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
            diag_type = DiagnosticType.VIOLATION,
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
        // runASTExport(file_path)  // TODO: Implement
        fmt.println("AST export not implemented yet")
        return
    }
    
    fmt.println("Processing file:", file_path)
    
    // Initialize tree-sitter AST parser
    ts_parser, ts_ok := initTreeSitterParser()
    if !ts_ok {
        internal_error := createInternalError(file_path, 1, 1, "Failed to initialize tree-sitter parser")
        emitDiagnostic(internal_error)
        deinitTreeSitterParser(ts_parser)
        os.exit(1)
    }
    
    // Parse file to get AST
    ast_root, parse_ok := parseFile(ts_parser, file_path)
    if !parse_ok {
        internal_error := createInternalError(file_path, 1, 1, "Failed to parse file - syntax error or unsupported Odin syntax")
        emitDiagnostic(internal_error)
        deinitTreeSitterParser(ts_parser)
        os.exit(1)
    }
    
    // Initialize rule registry
    registry := initRuleRegistry()
    
    // Register rules with Clippy-inspired categorization
    // Rule files now use descriptive naming: Cnnn-CAT-Description.odin
    registerRule(&registry, C001Rule())  // CORRECTNESS category (c001-COR-Memory.odin)
    registerRule(&registry, C002Rule())  // CORRECTNESS category (c002-COR-Pointer.odin)
    registerRule(&registry, C003Rule())  // STYLE category (c003-STY-Naming.odin)
    registerRule(&registry, C004Rule())  // STYLE category (c004-STY-Private.odin)
    registerRule(&registry, C005Rule())  // STYLE category (c005-STY-Internal.odin)
    registerRule(&registry, C006Rule())  // STYLE category (c006-STY-Public.odin)
    registerRule(&registry, C007Rule())  // STYLE category (c007-STY-Types.odin)
    registerRule(&registry, C008Rule())  // STYLE category (c008-STY-Acronyms.odin)
    
    // Apply all rules
    diagnostics_found := false
    // Apply C001 rule with parsed AST
    c001_rule := C001Rule()
    // Special handling for C001 which can return multiple diagnostics
    if c001_rule.id == "C001" {
        // Use the multi-diagnostic version for C001
        c001_diagnostics := c001Matcher(file_path, &ast_root)  // Import this from c001.odin
        
        // Remove duplicates before emitting
        unique_diagnostics := dedupDiagnostics(c001_diagnostics)
        
        for diag in unique_diagnostics {
            if diag.message != "" {
                emitDiagnostic(diag)
                diagnostics_found = true
            }
        }
    } else {
        // Add nil guard for rules that don't use Rule.matcher (like C002)
        if c001_rule.matcher != nil {
            diag := c001_rule.matcher(file_path, &ast_root)
            if diag.message != "" {
                emitDiagnostic(diag)
                diagnostics_found = true
            }
        }
    }
    
    // Apply C002 rule with parsed AST and fresh context
    // Note: c002Matcher is called directly due to signature mismatch with Rule.matcher
    c002_ctx := create_c002_context()
    c002_diagnostics := c002Matcher(file_path, &ast_root, &c002_ctx)
    
    // Remove duplicates before emitting
    unique_c002_diagnostics := dedupDiagnostics(c002_diagnostics)
    
    for diag2 in unique_c002_diagnostics {
        if diag2.message != "" {
            emitDiagnostic(diag2)
            diagnostics_found = true
        }
    }
    
    // SHADOW MODE: Run SCM C002 in parallel and compare outputs (debug builds only).
    // Once parity is confirmed, the SCM matcher replaces the manual walker.
    when ODIN_DEBUG {
        file_content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(file_content)
            file_lines := strings.split(string(file_content), "\n")

            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(file_content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root_tsnode := getRootNode(tree)
                if !ts_node_is_null(root_tsnode) {
                    // Dump parse tree to stderr for grammar debugging
                    tree_cstr := ts_node_string(root_tsnode)
                    tree_str  := strings.string_from_null_terminated_ptr(cast(^u8)tree_cstr, 1<<20)
                    fmt.eprintf("[TREE] %s\n", tree_str)

                    memory_query, query_ok := load_query(ts_parser.adapter.language, "ffi/tree_sitter/queries/memory_safety.scm")
                    if query_ok {
                        scm_diags := c002_scm_matcher(file_path, root_tsnode, file_lines, &memory_query)
                        unload_query(&memory_query)

                        if len(scm_diags) != len(unique_c002_diagnostics) {
                            fmt.eprintfln("[shadow] C002 parity FAIL: manual=%d SCM=%d for %s",
                                len(unique_c002_diagnostics), len(scm_diags), file_path)
                        } else {
                            fmt.eprintfln("[shadow] C002 parity OK: manual=%d SCM=%d", len(unique_c002_diagnostics), len(scm_diags))
                        }
                    }
                }
            }
        }
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