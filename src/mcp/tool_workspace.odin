package mcp_server

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

import mcp  "../../vendor/odin-mcp"
import core "../core"

// =============================================================================
// lint_workspace — batch lint an entire directory
// =============================================================================

make_lint_workspace_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "lint_workspace",
            description = "Run odin-lint on all .odin files under a directory. Returns all diagnostics as a JSON array.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Directory (or file) to lint recursively"
                    },
                    "rules": {
                        "type": "string",
                        "description": "Comma-separated rule IDs to run (e.g. C001,C002). Omit for all default rules."
                    }
                },
                "required": ["path"]
            }`,
        },
        handler = _lint_workspace_handler,
    }
}

@(private="file")
_lint_workspace_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    path, err := _extract_string_param(params, "path")
    if err != "" { return err, true }

    opts := core.LintOptions{recursive = true}

    if rules_str, rules_err := _extract_string_param(params, "rules"); rules_err == "" {
        parts := strings.split(rules_str, ",")
        defer delete(parts)
        for p in parts {
            trimmed := strings.trim(p, " \t")
            if trimmed != "" { append(&opts.rule_filter, trimmed) }
        }
    }

    collector := make([dynamic]core.Diagnostic, allocator)

    files := core.collect_odin_files([]string{path}, true, false)
    defer {
        for f in files { delete(f) }
        delete(files)
    }

    for file_path in files {
        core.analyze_file(file_path, &_ts_parser, opts, &collector)
    }

    return _diags_to_json(collector[:], allocator), false
}

// =============================================================================
// list_rules — return the full rule catalog as JSON
// =============================================================================

make_list_rules_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "list_rules",
            description = "Return the full odin-lint rule catalog as JSON: id, tier, error_class, description, fix_hint, enabled_by_default.",
            input_schema = `{"type": "object", "properties": {}}`,
        },
        handler = _list_rules_handler,
    }
}

RuleCatalogEntry :: struct {
    id:                string,
    tier:              string,
    error_class:       string,
    description:       string,
    fix_hint:          string,
    enabled_by_default: bool,
}

@(private="file")
_RULES :: []RuleCatalogEntry{
    {"C001", "correctness", "correctness_memory_leak",
     "Memory allocation without matching defer free",
     "Add `defer free(...)` or `defer delete(...)` after the allocation", true},
    {"C002", "correctness", "correctness_double_free",
     "Double-free or use-after-free of an allocation",
     "Remove the redundant free or restructure ownership", true},
    {"C003", "style", "style_naming_proc",
     "Procedure names must be snake_case",
     "Rename the procedure to snake_case", true},
    {"C007", "style", "style_naming_type",
     "Type/struct/enum names must be PascalCase",
     "Rename the type to PascalCase", true},
    {"C009", "correctness", "migration_deprecated_import",
     "Deprecated core:os/old import — use core:os instead",
     "Replace `import \\\"core:os/old\\\"` with `import \\\"core:os\\\"`", true},
    {"C010", "correctness", "migration_deprecated_fmt",
     "Deprecated fmt proc — Small_Array superseded by [dynamic]T",
     "Replace deprecated fmt call with current equivalent", true},
    {"C011", "correctness", "ffi_resource_leak",
     "FFI C resource allocated without paired cleanup (ts_*_new without defer)",
     "Add `defer ts_*_delete(...)` immediately after allocation", true},
    {"C012", "style", "style_ownership_naming",
     "Semantic ownership naming hints (opt-in)",
     "Follow ownership naming conventions for the resource type", false},
    {"C014", "style", "dead_code_unused_proc",
     "Unexported procedure is never called within the package",
     "Remove the unused procedure or export it if needed", false},
    {"C015", "style", "dead_code_unused_const",
     "Unexported constant is never referenced within the package",
     "Remove the unused constant or export it if needed", false},
    {"C016", "style", "style_naming_local_var",
     "Local variable names must be snake_case",
     "Rename the variable to snake_case", true},
    {"C017", "style", "style_naming_pkg_var",
     "Package-level variable names must be snake_case or _snake_case",
     "Rename the variable following the package-variable naming convention", true},
    {"C018", "style", "style_naming_visibility",
     "Visibility marker conventions violated",
     "Apply the correct visibility prefix (_private / exported)", true},
    {"C019", "style", "style_naming_type_marker",
     "Variable name does not match its type marker suffix convention (opt-in)",
     "Append the required suffix (e.g. _ptr, _slice, _map, _alloc)", false},
    {"C101", "correctness", "correctness_context_integrity",
     "context.allocator assigned without defer restore",
     "Add `defer context.allocator = context.allocator` before the assignment, or use `context := context`", true},
    {"C202", "correctness", "correctness_switch_exhaustiveness",
     "Switch on enum value is not exhaustive — one or more enum cases not handled",
     "Add the missing cases, add 'case _:' for a default, or use '#partial switch'", true},
    {"C201", "correctness", "correctness_unchecked_result",
     "Error return value is discarded — call result not assigned or checked",
     "Assign the result and handle the error, or use 'or_return'", true},
    {"C203", "correctness", "correctness_defer_scope_trap",
     "defer fires at inner block exit — handle assigned to outer scope becomes dangling (Odin defer is block-scoped, unlike Go)",
     "Move defer to the outer scope, or avoid storing the resource handle in outer variables", true},
    {"C021", "correctness", "correctness_go_fmt_call",
     "Go-style fmt.Println/Printf/Sprintf call — use Odin's lowercase equivalents",
     "Replace with: fmt.println, fmt.printf, fmt.tprintf/fmt.aprintf for formatting", false},
    {"C022", "correctness", "correctness_go_range_loop",
     "Go-style 'for i, v := range' loop — Odin uses 'for v, i in collection'",
     "Replace with: for value, index in collection { ... }", false},
    {"C023", "correctness", "correctness_go_deref_syntax",
     "C-style '*ptr' dereference — Odin uses postfix 'ptr^'",
     "Replace '*ptr' with 'ptr^'", false},
    {"C025", "correctness", "correctness_append_missing_addr",
     "append(slice, v) missing address-of — Odin's append takes a pointer to the slice (go_migration domain)",
     "Add & before first argument: change append(slice, ...) to append(&slice, ...)", false},
    {"C029", "correctness", "correctness_stdlib_alloc_leak",
     "stdlib allocating proc (strings.split/clone/join, fmt.aprintf, os.read_entire_file…) result not freed (stdlib_safety domain)",
     "Add 'defer delete(var)' immediately after the allocation", false},
    {"C033", "correctness", "correctness_builder_not_destroyed",
     "strings.builder_make() without matching defer strings.builder_destroy — internal buffer leaks (stdlib_safety domain)",
     "Add 'defer strings.builder_destroy(&sb)' immediately after strings.builder_make()", false},
    {"B001", "structural", "structure_unmatched_brace",
     "Unmatched brace — file has mismatched {{ or }}",
     "Fix brace balance", true},
    {"B002", "structural", "structure_package_name",
     "Inconsistent package name within a directory",
     "Ensure all files in the directory declare the same package name", true},
    {"B003", "structural", "structure_subfolder_clash",
     "Subfolder uses same package name as parent directory",
     "Give the subfolder a distinct package name", true},
}

@(private="file")
_list_rules_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    b := strings.builder_make(allocator)
    strings.write_string(&b, `{"rules":[`)
    for entry, i in _RULES {
        if i > 0 { strings.write_string(&b, ",") }
        strings.write_string(&b, `{"id":`)
        _json_str(&b, entry.id)
        strings.write_string(&b, `,"tier":`)
        _json_str(&b, entry.tier)
        strings.write_string(&b, `,"error_class":`)
        _json_str(&b, entry.error_class)
        strings.write_string(&b, `,"description":`)
        _json_str(&b, entry.description)
        strings.write_string(&b, `,"fix_hint":`)
        _json_str(&b, entry.fix_hint)
        strings.write_string(&b, `,"enabled_by_default":`)
        strings.write_string(&b, "true" if entry.enabled_by_default else "false")
        strings.write_string(&b, "}")
    }
    strings.write_string(&b, `]}`)
    return strings.to_string(b), false
}

// =============================================================================
// run_odin_check — invoke `odin check` as a subprocess and return diagnostics
// =============================================================================

make_run_odin_check_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "run_odin_check",
            description = "Run `odin check` on a file or directory and return compiler diagnostics as structured JSON. Complements odin-lint with type-checking and semantic errors that static analysis cannot detect.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File or directory to type-check (passed directly to odin check)"
                    },
                    "extra_flags": {
                        "type": "string",
                        "description": "Optional extra flags for odin check, e.g. -target:darwin_arm64 or -vet"
                    },
                    "odin_path": {
                        "type": "string",
                        "description": "Path to the odin executable (default: odin from PATH, or [tools] odin_path in olt.toml)"
                    }
                },
                "required": ["path"]
            }`,
        },
        handler = _run_odin_check_handler,
    }
}

// OdinCheckDiag holds one parsed compiler diagnostic line.
@(private="file")
OdinCheckDiag :: struct {
    file:    string,
    line:    int,
    column:  int,
    level:   string,  // "error", "warning", "note"
    message: string,
}

@(private="file")
_run_odin_check_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    path, err := _extract_string_param(params, "path")
    if err != "" { return err, true }

    // Build command: ["odin", "check", <path>, ...extra_flags]
    odin_exe := "odin"
    if op, op_err := _extract_string_param(params, "odin_path"); op_err == "" && op != "" {
        odin_exe = op
    }

    cmd := make([dynamic]string, allocator)
    append(&cmd, odin_exe)
    append(&cmd, "check")
    append(&cmd, path)

    if extra, extra_err := _extract_string_param(params, "extra_flags"); extra_err == "" && extra != "" {
        parts := strings.split(extra, " ")
        defer delete(parts)
        for p in parts {
            trimmed := strings.trim(p, " \t")
            if trimmed != "" { append(&cmd, trimmed) }
        }
    }

    state, stdout_bytes, stderr_bytes, exec_err := os.process_exec(
        os.Process_Desc{command = cmd[:]},
        allocator,
    )
    defer delete(stdout_bytes)
    defer delete(stderr_bytes)

    if exec_err != nil {
        msg := fmt.aprintf("odin check failed to launch: %v", exec_err, allocator)
        b_err := strings.builder_make(allocator)
        strings.write_string(&b_err, `{"ok":false,"error":`)
        _json_str(&b_err, msg)
        strings.write_string(&b_err, `,"diagnostics":[]}`)
        return strings.to_string(b_err), true
    }

    // odin check writes errors to stderr; stdout may have build output.
    combined_parts := make([dynamic]string, context.temp_allocator)
    if len(stderr_bytes) > 0 { append(&combined_parts, string(stderr_bytes)) }
    if len(stdout_bytes) > 0 { append(&combined_parts, string(stdout_bytes)) }
    combined := strings.concatenate(combined_parts[:], allocator)

    diags := make([dynamic]OdinCheckDiag, allocator)
    lines := strings.split_lines(combined)
    defer delete(lines)
    for raw_line in lines {
        if d, ok := _parse_odin_check_line(raw_line); ok {
            append(&diags, d)
        }
    }

    error_count   := 0
    warning_count := 0
    for d in diags {
        if d.level == "error"   { error_count   += 1 }
        if d.level == "warning" { warning_count += 1 }
    }

    b := strings.builder_make(allocator)
    strings.write_string(&b, `{"ok":`)
    strings.write_string(&b, "true" if state.success else "false")
    fmt.sbprintf(&b, `,"exit_code":%d,"error_count":%d,"warning_count":%d,"diagnostics":[`,
        state.exit_code, error_count, warning_count)

    for d, i in diags {
        if i > 0 { strings.write_string(&b, ",") }
        strings.write_string(&b, `{"file":`)
        _json_str(&b, d.file)
        fmt.sbprintf(&b, `,"line":%d,"column":%d,"level":`, d.line, d.column)
        _json_str(&b, d.level)
        strings.write_string(&b, `,"message":`)
        _json_str(&b, d.message)
        strings.write_string(&b, "}")
    }
    strings.write_string(&b, `],"raw_output":`)
    _json_str(&b, combined)
    strings.write_string(&b, "}")
    return strings.to_string(b), false
}

// _parse_odin_check_line attempts to parse a single line of `odin check` output.
// Odin compiler format: /path/file.odin(line:col) Level: message
// Returns the parsed diagnostic and true on success; zero value + false otherwise.
@(private="file")
_parse_odin_check_line :: proc(raw: string) -> (OdinCheckDiag, bool) {
    line := strings.trim(raw, " \t\r")
    if len(line) == 0 { return {}, false }

    // Find opening paren — the location marker.
    paren_open := strings.last_index(line, "(")
    if paren_open < 0 { return {}, false }
    paren_close := strings.index(line[paren_open:], ")")
    if paren_close < 0 { return {}, false }
    paren_close += paren_open

    file_part  := strings.trim(line[:paren_open], " \t")
    loc_part   := line[paren_open+1:paren_close]  // "42:5"
    after_paren := strings.trim(line[paren_close+1:], " \t")

    if len(file_part) == 0 || len(loc_part) == 0 { return {}, false }

    // Parse "line:col"
    colon := strings.index(loc_part, ":")
    if colon < 0 { return {}, false }
    line_num, line_ok := strconv.parse_int(loc_part[:colon])
    col_num,  col_ok  := strconv.parse_int(loc_part[colon+1:])
    if !line_ok || !col_ok { return {}, false }

    // Parse level from "Error: ..." / "Warning: ..." / "Note: ..."
    level   := "error"
    message := after_paren
    if strings.has_prefix(after_paren, "Error: ") {
        level   = "error"
        message = after_paren[7:]
    } else if strings.has_prefix(after_paren, "Warning: ") {
        level   = "warning"
        message = after_paren[9:]
    } else if strings.has_prefix(after_paren, "Note: ") {
        level   = "note"
        message = after_paren[6:]
    } else if strings.has_prefix(after_paren, "Syntax Error: ") {
        level   = "error"
        message = after_paren[14:]
    } else {
        return {}, false  // not a recognised diagnostic line
    }

    return OdinCheckDiag{
        file    = file_part,
        line    = line_num,
        column  = col_num,
        level   = level,
        message = message,
    }, true
}
