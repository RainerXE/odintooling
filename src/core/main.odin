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

// analyzeWithBlocks performs block-aware AST analysis
analyzeWithBlocks :: proc(analyzer: ^BlockAnalyzer, node: ^ASTNode, file_path: string) {
    // Traverse the AST with scope awareness
    traverseASTWithScope(analyzer, node, file_path)
}

// traverseASTWithScope traverses AST while managing scope stack
traverseASTWithScope :: proc(analyzer: ^BlockAnalyzer, node: ^ASTNode, file_path: string) {
    // Determine node type and handle accordingly
    switch node.node_type {
        case "source_file":
            // Source file is the root - traverse children
            for &child in node.children {
                traverseASTWithScope(analyzer, &child, file_path)
            }
            
        case "block":
            // Push new block scope
            pushScope(analyzer, node, BlockType.BLOCK)
            
            // Analyze statements in this block
            for &child in node.children {
                analyzeStatement(analyzer, &child, file_path)
            }
            
            // Pop scope and validate
            _, diagnostics := popScope(analyzer)
            for &diag in diagnostics {
                diag.file = file_path
                addDiagnostic(analyzer, diag)
            }
            
        case "procedure_declaration":
            // Procedure creates a new scope
            pushScope(analyzer, node, BlockType.PROCEDURE)
            
            // Analyze procedure body
            for &child in node.children {
                traverseASTWithScope(analyzer, &child, file_path)
            }
            
            // Pop scope and validate
            _, diagnostics := popScope(analyzer)
            for &diag in diagnostics {
                diag.file = file_path
                addDiagnostic(analyzer, diag)
            }
            
        case "if_statement":
            // If statement with potential blocks
            pushScope(analyzer, node, BlockType.IF)
            for &child in node.children {
                traverseASTWithScope(analyzer, &child, file_path)
            }
            _, diagnostics := popScope(analyzer)
            for &diag in diagnostics {
                diag.file = file_path
                addDiagnostic(analyzer, diag)
            }
            
        case "for_statement":
            pushScope(analyzer, node, BlockType.FOR)
            for child in node.children {
                traverseASTWithScope(analyzer, &child, file_path)
            }
            _, diagnostics := popScope(analyzer)
            for diag in diagnostics {
                diag.file = file_path
                addDiagnostic(analyzer, diag)
            }
            
        case "while_statement":
            pushScope(analyzer, node, BlockType.WHILE)
            for child in node.children {
                traverseASTWithScope(analyzer, &child, file_path)
            }
            _, diagnostics := popScope(analyzer)
            for diag in diagnostics {
                diag.file = file_path
                addDiagnostic(analyzer, diag)
            }
            
        default:
            // Handle other node types
            analyzeStatement(analyzer, node, file_path)
    }
}

// analyzeStatement analyzes individual statements within a scope
analyzeStatement :: proc(analyzer: ^BlockAnalyzer, node: ^ASTNode, file_path: string) {
    current_scope := getCurrentScope(analyzer)
    if current_scope == nil {
        return
    }
    
    switch node.node_type {
        case "assignment_statement":
            // Check for allocations: data := make(...)
            if len(node.children) >= 3 {
                if node.children[1].text == ":=" {  // Assignment operator
                    // Check if right side is an allocation call
                    for i in 2..<len(node.children) {
                        if node.children[i].node_type == "call_expression" {
                            // This might be an allocation
                            alloc := Allocation{
                                node = &node.children[i],
                                variable = node.children[0].text,  // Left side variable
                                line = node.start_line,
                                col = node.start_column,
                                function = "unknown",  // TODO: Extract function name
                                is_freed = false,
                            }
                            trackAllocation(analyzer, alloc)
                            break
                        }
                    }
                }
            }
            
        case "defer_statement":
            // Track defer statements
            defer_stmt := DeferStatement{
                node = node,
                line = node.start_line,
                col = node.start_column,
                function = "unknown",  // TODO: Extract function name
                target = "unknown",    // TODO: Extract target variable
            }
            trackDefer(analyzer, defer_stmt)
            
        case "variable_declaration":
            // Track variable declarations
            var_name := ""
            var_type := ""
            
            // Extract variable name and type
            for &child in node.children {
                if child.node_type == "identifier" && var_name == "" {
                    var_name = child.text
                }
                if child.node_type == "type" {
                    var_type = child.text
                }
            }
            
            if var_name != "" {
                var_info := VariableInfo{
                    name = var_name,
                    declaration = node,
                    line = node.start_line,
                    col = node.start_column,
                    type = var_type,
                    is_used = false,
                    is_freed = false,
                }
                trackVariable(analyzer, var_info)
            }
            
        // Add more statement types as needed
    }
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
        // runASTExport(file_path)  // TODO: Implement
        fmt.println("AST export not implemented yet")
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
    
    // Initialize block analyzer for scope-aware analysis
    block_analyzer := initBlockAnalyzer()
    
    // Perform block-based analysis of the AST
    analyzeWithBlocks(&block_analyzer, &ast_root, file_path)
    
    // Get diagnostics from block analyzer
    block_diagnostics := getDiagnostics(&block_analyzer)
    
    // Apply diagnostics from block analysis
    for &diag in block_diagnostics {
        // Set the file path for each diagnostic
        diag.file = file_path
        emitDiagnostic(diag)
        diagnostics_found = true
    }
    
    // Also run stub rule for now (will be removed later)
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