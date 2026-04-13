package core

import "core:fmt"
import "core:os"
import "core:strings"

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
    file:      string,
    line:      int,
    column:    int,
    rule_id:   string,
    tier:      string,
    message:   string,
    fix:       string,
    has_fix:   bool,
    diag_type: DiagnosticType,
}

// Rule represents a linting rule
Rule :: struct {
    id:       string,
    tier:     string,
    category: RuleCategory,
    matcher:  proc(file_path: string, node: ^ASTNode) -> Diagnostic,
    message:  proc() -> string,
    fix_hint: proc() -> string,
}

// RuleRegistry manages all linting rules
RuleRegistry :: struct {
    rules: map[string]Rule,
}

initRuleRegistry :: proc() -> RuleRegistry {
    return RuleRegistry{rules = make(map[string]Rule)}
}

registerRule :: proc(registry: ^RuleRegistry, rule: Rule) {
    registry.rules[rule.id] = rule
}

getRule :: proc(registry: RuleRegistry, id: string) -> (Rule, bool) {
    rule, ok := registry.rules[id]
    return rule, ok
}

// emitDiagnostic prints a diagnostic with appropriate formatting.
emitDiagnostic :: proc(diag: Diagnostic) {
    switch diag.diag_type {
    case .INTERNAL_ERROR:
        fmt.printf("🟣 %s:%d:%d: INTERNAL ERROR - %s", diag.file, diag.line, diag.column, diag.message)
    case .CONTEXTUAL:
        fmt.printf("🟡 %s:%d:%d: %s [%s] %s", diag.file, diag.line, diag.column, diag.rule_id, diag.tier, diag.message)
    case .INFO:
        fmt.printf("🔵 %s:%d:%d: INFO - %s", diag.file, diag.line, diag.column, diag.message)
    case .VIOLATION, .NONE:
        fmt.printf("🔴 %s:%d:%d: %s [%s] %s", diag.file, diag.line, diag.column, diag.rule_id, diag.tier, diag.message)
    }
    if diag.has_fix { fmt.printf("\nFix: %s", diag.fix) }
    fmt.println()
}

// dedupDiagnostics removes exact duplicate diagnostics (same file:line:col:rule).
dedupDiagnostics :: proc(diags: []Diagnostic) -> []Diagnostic {
    seen   := make(map[string]bool)
    result := make([dynamic]Diagnostic)
    for d in diags {
        key := fmt.tprintf("%s:%d:%d:%s", d.file, d.line, d.column, d.rule_id)
        if key not_in seen {
            seen[key] = true
            append(&result, d)
        }
    }
    return result[:]
}

// createInternalError creates an internal error diagnostic.
createInternalError :: proc(file_path: string, line: int, column: int, msg: string) -> Diagnostic {
    return Diagnostic{
        file      = file_path,
        line      = line,
        column    = column,
        rule_id   = "INTERNAL",
        tier      = "error",
        message   = msg,
        fix       = "This is a linter internal error — please report at https://github.com/anthropics/claude-code/issues",
        has_fix   = false,
        diag_type = DiagnosticType.INTERNAL_ERROR,
    }
}

// =============================================================================
// Per-file analysis
// =============================================================================

// analyze_file runs all enabled lint passes on a single .odin file.
// Returns (violation_count, had_internal_error).
analyze_file :: proc(
    file_path: string,
    ts_parser: ^TreeSitterASTParser,
    opts:      LintOptions,
) -> (int, bool) {
    violations := 0

    // C001: Memory allocation without defer free (OdinLint AST walker)
    if rule_enabled("C001", "correctness", opts) {
        ast_root, parse_ok := parseFile(ts_parser^, file_path)
        if !parse_ok {
            emitDiagnostic(createInternalError(file_path, 1, 1,
                "failed to parse file — syntax error or unsupported Odin syntax"))
            return violations, true
        }
        for d in dedupDiagnostics(c001Matcher(file_path, &ast_root)) {
            if d.message != "" { emitDiagnostic(d); violations += 1 }
        }
    }

    // C002: Double-free detection (tree-sitter SCM)
    if rule_enabled("C002", "correctness", opts) {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(content)
            lines := strings.split(string(content), "\n")
            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root := getRootNode(tree)
                if !ts_node_is_null(root) {
                    q, q_ok := load_query_src(ts_parser.adapter.language, MEMORY_SAFETY_SCM, "memory_safety.scm")
                    if q_ok {
                        diags := c002_scm_matcher(file_path, root, lines, &q)
                        unload_query(&q)
                        for d in dedupDiagnostics(diags) {
                            if d.message != "" { emitDiagnostic(d); violations += 1 }
                        }
                    }
                }
            }
        }
    }

    // C003 + C007: Naming rules (shared SCM pass)
    if rule_enabled("C003", "style", opts) || rule_enabled("C007", "style", opts) {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(content)
            lines := strings.split(string(content), "\n")
            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root := getRootNode(tree)
                if !ts_node_is_null(root) {
                    q, q_ok := load_query_src(ts_parser.adapter.language, NAMING_RULES_SCM, "naming_rules.scm")
                    if q_ok {
                        diags := naming_scm_run(file_path, root, lines, &q)
                        unload_query(&q)
                        for d in dedupDiagnostics(diags) {
                            if d.message != "" { emitDiagnostic(d); violations += 1 }
                        }
                    }
                }
            }
        }
    }

    // C009 + C010: Odin 2026 migration (shared SCM pass)
    if rule_enabled("C009", "correctness", opts) || rule_enabled("C010", "correctness", opts) {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(content)
            lines := strings.split(string(content), "\n")
            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root := getRootNode(tree)
                if !ts_node_is_null(root) {
                    q, q_ok := load_query_src(ts_parser.adapter.language, ODIN2026_SCM, "odin2026_migration.scm")
                    if q_ok {
                        if rule_enabled("C009", "correctness", opts) {
                            for d in dedupDiagnostics(c009_scm_run(file_path, root, lines, &q)) {
                                if d.message != "" { emitDiagnostic(d); violations += 1 }
                            }
                        }
                        if rule_enabled("C010", "correctness", opts) {
                            for d in dedupDiagnostics(c010_scm_run(file_path, root, lines, &q)) {
                                if d.message != "" { emitDiagnostic(d); violations += 1 }
                            }
                        }
                        unload_query(&q)
                    }
                }
            }
        }
    }

    // C011: FFI safety — ts_*_new without defer ts_*_delete
    if rule_enabled("C011", "correctness", opts) {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(content)
            lines := strings.split(string(content), "\n")
            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root := getRootNode(tree)
                if !ts_node_is_null(root) {
                    q, q_ok := load_query_src(ts_parser.adapter.language, FFI_SAFETY_SCM, "ffi_safety.scm")
                    if q_ok {
                        diags := c011_scm_run(file_path, root, lines, &q)
                        unload_query(&q)
                        for d in dedupDiagnostics(diags) {
                            if d.message != "" { emitDiagnostic(d); violations += 1 }
                        }
                    }
                }
            }
        }
    }

    // C012: Semantic ownership naming (opt-in)
    if rule_enabled("C012", "style", opts) {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err == nil {
            defer delete(content)
            lines := strings.split(string(content), "\n")
            tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
            if tree_ok {
                defer ts_tree_delete(tree)
                root := getRootNode(tree)
                if !ts_node_is_null(root) {
                    q, q_ok := load_query_src(ts_parser.adapter.language, C012_RULES_SCM, "c012_rules.scm")
                    if q_ok {
                        diags := c012_scm_run(file_path, root, lines, &q)
                        unload_query(&q)
                        for d in dedupDiagnostics(diags) {
                            if d.message != "" { emitDiagnostic(d); violations += 1 }
                        }
                    }
                }
            }
        }
    }

    return violations, false
}

// =============================================================================
// Entry point
// =============================================================================

// main delegates to _main so that defers run cleanly before os.exit.
main :: proc() {
    os.exit(_main())
}

_main :: proc() -> int {
    opts, parse_ok := parse_args(os.args[1:])
    if !parse_ok { return 2 }

    if opts.show_version { print_version(); return 0 }
    if opts.show_help    { print_help();    return 0 }
    if opts.list_rules   { print_list_rules(); return 0 }

    if len(opts.targets) == 0 {
        fmt.eprintln("error: no target specified. Run 'odin-lint --help' for usage.")
        return 2
    }

    // Collect all .odin files from targets
    files := collect_odin_files(opts.targets[:], opts.recursive, opts.include_vendor)
    defer {
        for f in files { delete(f) }
        delete(files)
    }

    if len(files) == 0 {
        fmt.eprintln("warning: no .odin files found in specified targets")
        return 0
    }

    ts_parser, ts_ok := initTreeSitterParser()
    if !ts_ok {
        fmt.eprintln("error: failed to initialize tree-sitter parser")
        return 2
    }
    defer deinitTreeSitterParser(ts_parser)

    total_violations      := 0
    files_with_violations := 0
    had_error             := false

    for file_path in files {
        v, err := analyze_file(file_path, &ts_parser, opts)
        if err { had_error = true; continue }
        if v > 0 {
            total_violations      += v
            files_with_violations += 1
        }
    }

    if had_error { return 2 }

    if total_violations > 0 {
        fmt.printf("%d violation(s) in %d file(s)\n", total_violations, files_with_violations)
        return 1
    }

    if len(files) == 1 {
        fmt.println("No diagnostics found")
    } else {
        fmt.printf("No violations found in %d file(s)\n", len(files))
    }
    return 0
}
