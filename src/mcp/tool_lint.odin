// mcp/tool_lint.odin — lint_file, lint_snippet, and lint_fix MCP tools.
// lint_file lints a file on disk; lint_snippet lints in-memory source text;
// lint_fix applies --fix to a file and returns a before/after diff.
package mcp_server

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

import mcp  "../../vendor/odin-mcp/mcp"
import core "../core"

// ── Tier 1 tools: direct odin-lint analysis, no OLS subprocess ───────────────

// make_lint_file_tool runs all rules on a file at the given path.
make_lint_file_tool :: proc() -> mcp.Tool {
    return mcp.Tool{
        defn = mcp.ToolDefinition{
            name        = "lint_file",
            description = "Run odin-lint on an Odin source file. Returns all violations as JSON.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Absolute path to the .odin file to lint"
                    },
                    "format": {
                        "type": "string",
                        "enum": ["full", "lint"],
                        "description": "Output shape: full (default, includes rule_id/error_class/tier/column/fix) or lint (exactly file,line,col,severity,code,message,symbol)"
                    }
                },
                "required": ["path"]
            }`,
        },
        simple_handler = _lint_file_handler,
    }
}

@(private="file")
_lint_file_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> mcp.Tool_Result {
    path, err := _extract_string_param(params, "path")
    if err != "" { return mcp.tool_error(.Invalid_Params, err, allocator) }

    if !os.exists(path) {
        return mcp.tool_error(.Not_Found, fmt.tprintf("file not found: %s", path), allocator)
    }

    lint_shape, format_err := _lint_format_mode(params)
    if format_err != "" { return mcp.tool_error(.Invalid_Params, format_err, allocator) }

    opts := core.LintOptions{recursive = false}

    collector := make([dynamic]core.Diagnostic, allocator)
    core.analyze_file(path, &_ts_parser, opts, &collector)

    if lint_shape {
        return mcp.tool_ok(_diags_to_lint_json(collector[:], allocator), allocator)
    }
    return mcp.tool_ok(_diags_to_json(collector[:], allocator), allocator)
}

// make_lint_snippet_tool runs all rules on in-memory Odin source text.
make_lint_snippet_tool :: proc() -> mcp.Tool {
    return mcp.Tool{
        defn = mcp.ToolDefinition{
            name        = "lint_snippet",
            description = "Run odin-lint on an in-memory Odin source snippet. No file I/O performed.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "Odin source code to lint"
                    },
                    "filename": {
                        "type": "string",
                        "description": "Virtual filename used in diagnostics (default: snippet.odin)"
                    },
                    "format": {
                        "type": "string",
                        "enum": ["full", "lint"],
                        "description": "Output shape: full (default) or lint (exactly file,line,col,severity,code,message,symbol)"
                    }
                },
                "required": ["source"]
            }`,
        },
        simple_handler = _lint_snippet_handler,
    }
}

@(private="file")
_lint_snippet_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> mcp.Tool_Result {
    source, err := _extract_string_param(params, "source")
    if err != "" { return mcp.tool_error(.Invalid_Params, err, allocator) }

    filename := "snippet.odin"
    if fn, fn_err := _extract_string_param(params, "filename"); fn_err == "" {
        filename = fn
    }
    lint_shape, format_err := _lint_format_mode(params)
    if format_err != "" { return mcp.tool_error(.Invalid_Params, format_err, allocator) }

    collector := make([dynamic]core.Diagnostic, allocator)
    core.analyze_content(filename, source, &_ts_parser, &collector)

    if lint_shape {
        return mcp.tool_ok(_diags_to_lint_json(collector[:], allocator), allocator)
    }
    return mcp.tool_ok(_diags_to_json(collector[:], allocator), allocator)
}

// make_lint_fix_tool returns proposed fixes for a file without writing to disk.
make_lint_fix_tool :: proc() -> mcp.Tool {
    return mcp.Tool{
        defn = mcp.ToolDefinition{
            name        = "lint_fix",
            description = "Return proposed odin-lint fixes for a file as JSON. Does NOT write to disk.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Absolute path to the .odin file"
                    },
                    "rule_id": {
                        "type": "string",
                        "description": "Optional: only return fixes for this rule (e.g. C001). Omit for all rules."
                    }
                },
                "required": ["path"]
            }`,
        },
        simple_handler = _lint_fix_handler,
    }
}

@(private="file")
_lint_fix_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> mcp.Tool_Result {
    path, err := _extract_string_param(params, "path")
    if err != "" { return mcp.tool_error(.Invalid_Params, err, allocator) }

    if !os.exists(path) {
        return mcp.tool_error(.Not_Found, fmt.tprintf("file not found: %s", path), allocator)
    }

    opts := core.LintOptions{recursive = false}

    // Optional rule filter.
    if rule_id, rule_err := _extract_string_param(params, "rule_id"); rule_err == "" {
        append(&opts.rule_filter, rule_id)
    }

    collector := make([dynamic]core.Diagnostic, allocator)
    core.analyze_file(path, &_ts_parser, opts, &collector)

    fixes := core.generate_fixes(collector[:], false)
    defer delete(fixes)

    return mcp.tool_ok(_fixes_to_json(fixes[:], allocator), allocator)
}

// ── JSON serialisation helpers ────────────────────────────────────────────────

// _diags_to_json serialises a []Diagnostic slice to a JSON array string.
@(private)
_diags_to_json :: proc(diags: []core.Diagnostic, allocator: runtime.Allocator) -> string {
    b := strings.builder_make(allocator)
    strings.write_byte(&b, '[')
    for d, i in diags {
        if i > 0 { strings.write_byte(&b, ',') }
        strings.write_string(&b, `{"file":`)
        _json_str(&b, d.file)
        strings.write_string(&b, `,"line":`)
        fmt.sbprint(&b, d.line)
        strings.write_string(&b, `,"column":`)
        fmt.sbprint(&b, d.column)
        strings.write_string(&b, `,"col":`)
        fmt.sbprint(&b, d.column)
        strings.write_string(&b, `,"rule_id":`)
        _json_str(&b, d.rule_id)
        strings.write_string(&b, `,"code":`)
        _json_str(&b, d.rule_id)
        strings.write_string(&b, `,"error_class":`)
        _json_str(&b, core.rule_id_to_error_class(d.rule_id))
        strings.write_string(&b, `,"tier":`)
        _json_str(&b, d.tier)
        strings.write_string(&b, `,"severity":`)
        _json_str(&b, core.diagnostic_severity(d))
        strings.write_string(&b, `,"message":`)
        _json_str(&b, d.message)
        strings.write_string(&b, `,"symbol":`)
        _json_str(&b, d.symbol)
        if d.has_fix {
            strings.write_string(&b, `,"fix":`)
            _json_str(&b, d.fix)
        }
        strings.write_byte(&b, '}')
    }
    strings.write_byte(&b, ']')
    return strings.to_string(b)
}

// _diags_to_lint_json serialises diagnostics with exactly the seven keys of
// `olt --format lint`: file, line, col, severity, code, message, symbol.
@(private)
_diags_to_lint_json :: proc(diags: []core.Diagnostic, allocator: runtime.Allocator) -> string {
    b := strings.builder_make(allocator)
    strings.write_byte(&b, '[')
    for d, i in diags {
        if i > 0 { strings.write_byte(&b, ',') }
        strings.write_string(&b, `{"file":`)
        _json_str(&b, d.file)
        strings.write_string(&b, `,"line":`)
        fmt.sbprint(&b, d.line)
        strings.write_string(&b, `,"col":`)
        fmt.sbprint(&b, d.column)
        strings.write_string(&b, `,"severity":`)
        _json_str(&b, core.diagnostic_severity(d))
        strings.write_string(&b, `,"code":`)
        _json_str(&b, d.rule_id)
        strings.write_string(&b, `,"message":`)
        _json_str(&b, d.message)
        strings.write_string(&b, `,"symbol":`)
        _json_str(&b, d.symbol)
        strings.write_byte(&b, '}')
    }
    strings.write_byte(&b, ']')
    return strings.to_string(b)
}

// _fixes_to_json serialises a []FixEdit slice to a JSON array string.
@(private="file")
_fixes_to_json :: proc(fixes: []core.FixEdit, allocator: runtime.Allocator) -> string {
    b := strings.builder_make(allocator)
    strings.write_byte(&b, '[')
    for f, i in fixes {
        if i > 0 { strings.write_byte(&b, ',') }
        strings.write_string(&b, `{"file":`)
        _json_str(&b, f.file)
        strings.write_string(&b, `,"line":`)
        fmt.sbprint(&b, f.line)
        strings.write_string(&b, `,"rule_id":`)
        _json_str(&b, f.rule_id)
        strings.write_string(&b, `,"message":`)
        _json_str(&b, f.message)
        strings.write_string(&b, `,"new_text":`)
        _json_str(&b, f.new_text)
        strings.write_string(&b, `,"replace_line":`)
        strings.write_string(&b, "true" if f.replace_line else "false")
        strings.write_string(&b, `,"is_unsafe":`)
        strings.write_string(&b, "true" if f.is_unsafe else "false")
        strings.write_byte(&b, '}')
    }
    strings.write_byte(&b, ']')
    return strings.to_string(b)
}

// _lint_format_mode selects the full diagnostic payload or the exact seven-key
// lint channel shape. The default remains "full", so existing MCP consumers do
// not change.
@(private)
_lint_format_mode :: proc(params: json.Value) -> (lint_shape: bool, err: string) {
    format := _lint_opt_string(params, "format", "full")
    switch format {
    case "", "full":
        return false, ""
    case "lint":
        return true, ""
    case:
        return false, fmt.tprintf("unknown format '%s'; use 'full' or 'lint'", format)
    }
}

@(private)
_lint_opt_string :: proc(params: json.Value, key: string, default_val: string) -> string {
    obj, ok := params.(json.Object)
    if !ok { return default_val }
    val, exists := obj[key]
    if !exists { return default_val }
    s, s_ok := val.(json.String)
    if !s_ok { return default_val }
    return string(s)
}

// _extract_string_param pulls a string field from the tool params json.Value.
// Returns ("", "") on success; ("", error_message) on failure.
@(private)
_extract_string_param :: proc(params: json.Value, key: string) -> (value: string, err: string) {
    obj, is_obj := params.(json.Object)
    if !is_obj { return "", "params must be a JSON object" }
    val, has_key := obj[key]
    if !has_key { return "", fmt.tprintf("missing required parameter '%s'", key) }
    s, is_str := val.(json.String)
    if !is_str { return "", fmt.tprintf("parameter '%s' must be a string", key) }
    return string(s), ""
}

// _json_str writes a JSON-escaped quoted string into b.
@(private)
_json_str :: proc(b: ^strings.Builder, s: string) {
    strings.write_byte(b, '"')
    for c in s {
        switch c {
        case '"':  strings.write_string(b, `\"`)
        case '\\': strings.write_string(b, `\\`)
        case '\n': strings.write_string(b, `\n`)
        case '\r': strings.write_string(b, `\r`)
        case '\t': strings.write_string(b, `\t`)
        case:      strings.write_rune(b, c)
        }
    }
    strings.write_byte(b, '"')
}
