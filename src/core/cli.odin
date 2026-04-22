package core

import "core:fmt"
import "core:strings"

// append_rule_list splits a comma-separated rule string and appends each ID to dest.
@(private)
append_rule_list :: proc(raw: string, dest: ^[dynamic]string) {
    parts := strings.split(raw, ",")
    defer delete(parts)
    for part in parts {
        trimmed := strings.trim(part, " \t\r\n")
        if len(trimmed) > 0 { append(dest, strings.clone(trimmed)) }
    }
}

// =============================================================================
// CLI — argument parsing, version, help, rule listing
// =============================================================================

ODIN_LINT_VERSION    :: "0.4.0"
ODIN_GRAMMAR_VERSION :: "dev-2026-04"

LintOptions :: struct {
    targets:          [dynamic]string,
    recursive:        bool,            // default true
    include_vendor:   bool,            // default false
    rule_filter:      [dynamic]string, // empty = all rules
    tier_filter:      string,          // "" = all tiers
    c012_enabled:     bool,
    format:           string,          // "text" (default), "json", "sarif"
    explain_rule:     string,          // rule ID for --explain, or ""
    fix_mode:         bool,            // --fix: apply safe machine-applicable fixes in-place
    unsafe_fix_mode:  bool,            // --unsafe-fix: apply fixes that change API surface
    propose_mode:     bool,            // --propose: show proposed fixes without writing
    export_symbols:   bool,            // --export-symbols: build code graph + symbols.json
    graph_db_path:    string,          // --db: output path for graph db (default GRAPH_DB_PATH)
    show_help:        bool,
    show_version:     bool,
    list_rules:       bool,
    config:           OdinLintConfig,  // loaded from odin-lint.toml (or auto-detected)
}

// parse_args parses os.args[1:] into LintOptions.
// Returns (opts, true) on success, (opts, false) on usage error.
parse_args :: proc(args: []string) -> (LintOptions, bool) {
    opts := LintOptions{recursive = true}

    i := 0
    for i < len(args) {
        arg := args[i]
        switch {
        case arg == "--help" || arg == "-h":
            opts.show_help = true
        case arg == "--version":
            opts.show_version = true
        case arg == "--list-rules":
            opts.list_rules = true
        case arg == "--non-recursive":
            opts.recursive = false
        case arg == "--include-vendor":
            opts.include_vendor = true
        case arg == "--enable-c012":
            opts.c012_enabled = true
        case arg == "--fix":
            opts.fix_mode = true
        case arg == "--unsafe-fix":
            opts.unsafe_fix_mode = true
            opts.fix_mode        = true  // unsafe-fix implies fix
        case arg == "--propose":
            opts.propose_mode = true
        case arg == "--export-symbols":
            opts.export_symbols = true
        case strings.has_prefix(arg, "--db="):
            opts.graph_db_path = arg[len("--db="):]
        case arg == "--db":
            if i+1 >= len(args) {
                fmt.eprintln("error: --db requires a path argument")
                return opts, false
            }
            i += 1
            opts.graph_db_path = args[i]
        case arg == "--ast":
            // legacy flag, silently ignored
        case strings.has_prefix(arg, "--format="):
            val := arg[len("--format="):]
            if val != "text" && val != "json" && val != "sarif" {
                fmt.eprintfln("error: unknown format '%s'. Valid formats: text, json, sarif", val)
                return opts, false
            }
            opts.format = val
        case arg == "--format":
            if i+1 >= len(args) {
                fmt.eprintln("error: --format requires a value (text, json, sarif)")
                return opts, false
            }
            i += 1
            val := args[i]
            if val != "text" && val != "json" && val != "sarif" {
                fmt.eprintfln("error: unknown format '%s'. Valid formats: text, json, sarif", val)
                return opts, false
            }
            opts.format = val
        case arg == "--explain":
            if i+1 >= len(args) {
                fmt.eprintln("error: --explain requires a rule ID (e.g. --explain C001)")
                return opts, false
            }
            i += 1
            opts.explain_rule = args[i]
        case strings.has_prefix(arg, "--rule="):
            append_rule_list(arg[len("--rule="):], &opts.rule_filter)
        case arg == "--rule":
            if i+1 >= len(args) {
                fmt.eprintln("error: --rule requires a value (e.g. --rule C001,C002)")
                return opts, false
            }
            i += 1
            append_rule_list(args[i], &opts.rule_filter)
        case strings.has_prefix(arg, "--tier="):
            opts.tier_filter = arg[len("--tier="):]
        case arg == "--tier":
            if i+1 >= len(args) {
                fmt.eprintln("error: --tier requires a value (e.g. --tier correctness)")
                return opts, false
            }
            i += 1
            opts.tier_filter = args[i]
        case strings.has_prefix(arg, "--"):
            fmt.eprintfln("error: unknown flag '%s'", arg)
            return opts, false
        case:
            append(&opts.targets, arg)
        }
        i += 1
    }

    return opts, true
}

// rule_enabled returns true if the given rule should run given the current options.
rule_enabled :: proc(rule_id: string, tier: string, opts: LintOptions) -> bool {
    // Domain-gated rules: check config unless an explicit --rule filter overrides.
    explicitly_requested := false
    for r in opts.rule_filter { if r == rule_id { explicitly_requested = true; break } }

    // C012 can be enabled by --enable-c012 flag OR via semantic_naming domain.
    // Check the flag first so it can bypass the domain gate.
    if rule_id == "C012" {
        if !explicitly_requested && !opts.c012_enabled && !config_domain_enabled(rule_id, opts.config) {
            return false
        }
    } else if !explicitly_requested && !config_domain_enabled(rule_id, opts.config) {
        return false
    }

    if opts.tier_filter != "" && tier != opts.tier_filter { return false }
    if len(opts.rule_filter) == 0 { return true }
    for r in opts.rule_filter { if r == rule_id { return true } }
    return false
}

print_version :: proc() {
    fmt.printfln("odin-lint %s", ODIN_LINT_VERSION)
    fmt.printfln("supports Odin %s (grammar: %s)", ODIN_GRAMMAR_VERSION, ODIN_GRAMMAR_VERSION)
}

print_help :: proc() {
    fmt.println("Usage: odin-lint <target> [options]")
    fmt.println()
    fmt.println("Targets:")
    fmt.println("  file.odin          Lint a single file")
    fmt.println("  ./src/             Lint all .odin files (recursive by default)")
    fmt.println("  ./src/ file.odin   Multiple targets supported")
    fmt.println()
    fmt.println("Rules:")
    fmt.println("  C001  correctness  Memory allocation without matching defer free")
    fmt.println("  C002  correctness  Double-free or use-after-free")
    fmt.println("  C003  style        Proc names must be snake_case")
    fmt.println("  C007  style        Type names must be PascalCase")
    fmt.println("  C009  correctness  Deprecated core:os/old import")
    fmt.println("  C010  correctness  Small_Array superseded by [dynamic; N]T")
    fmt.println("  C011  correctness  FFI C resource allocated without paired cleanup")
    fmt.println("  C012  style        Semantic ownership naming hints (opt-in)")
    fmt.println("  C019  style        Type marker suffix conventions (opt-in, [naming] c019=true)")
    fmt.println("  C101  correctness  context.allocator assigned without defer restore")
    fmt.println()
    fmt.println("Options:")
    fmt.println("  --version              Print version and grammar info")
    fmt.println("  --help                 Show this help message")
    fmt.println("  --list-rules           List all rules (tab-separated: id, tier, message)")
    fmt.println("  --explain C001         Show detailed documentation for a rule")
    fmt.println("  --rule C001,C002       Run only the specified rules")
    fmt.println("  --tier correctness     Run only rules of the given tier (correctness|style)")
    fmt.println("  --format text|json|sarif  Output format (default: text)")
    fmt.println("  --non-recursive        Scan directories without recursing into subdirectories")
    fmt.println("  --include-vendor       Include vendor/ directories in scan")
    fmt.println("  --enable-c012          Enable C012 semantic ownership naming hints")
    fmt.println("  --fix                  Apply safe machine-applicable fixes in-place (C001)")
    fmt.println("  --unsafe-fix           Apply fixes that change API surface (e.g. C009 os2 migration)")
    fmt.println("  --propose              Show proposed fixes as a diff without writing")
    fmt.println()
    fmt.println("Exit codes:")
    fmt.println("  0  No violations found")
    fmt.println("  1  One or more violations found")
    fmt.println("  2  Usage error or internal failure")
}

print_list_rules :: proc() {
    fmt.println("C001\tcorrectness\tMemory allocation without matching defer free")
    fmt.println("C002\tcorrectness\tDouble-free or use-after-free")
    fmt.println("C003\tstyle\tProc names must be snake_case")
    fmt.println("C007\tstyle\tType names must be PascalCase")
    fmt.println("C009\tcorrectness\tDeprecated core:os/old import")
    fmt.println("C010\tcorrectness\tSmall_Array superseded by [dynamic; N]T")
    fmt.println("C011\tcorrectness\tFFI C resource allocated without paired cleanup")
    fmt.println("C012\tstyle\tSemantic ownership naming hints (opt-in)")
    fmt.println("C019\tstyle\tType marker suffix conventions (opt-in, [naming] c019=true in toml)")
    fmt.println("C101\tcorrectness\tcontext.allocator assigned without defer restore")
}
