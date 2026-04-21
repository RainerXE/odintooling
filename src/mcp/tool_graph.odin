package mcp_server

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "base:runtime"

import mcp  "../../vendor/odin-mcp"
import core "../core"

// =============================================================================
// get_dna_context
// =============================================================================

make_get_dna_context_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "get_dna_context",
            description = "Return callers, callees, memory role, return type, lint violations, and allocator-typed variables for a named Odin procedure.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "proc_name": {"type": "string", "description": "Exact procedure name to look up"},
                    "db_path":   {"type": "string", "description": "Path to graph db (default: .codegraph/odin_lint_graph.db)"}
                },
                "required": ["proc_name"]
            }`,
        },
        handler = _get_dna_context_handler,
    }
}

@(private="file")
_get_dna_context_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    proc_name, err := _extract_string_param(params, "proc_name")
    if err != "" { return err, true }
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    db, ok := core.graph_open(db_path)
    if !ok { return fmt.aprintf("graph db not found at %s — run --export-symbols first", db_path), true }
    defer core.graph_close(db)

    node, found := core.graph_get_node(db, proc_name)
    if !found { return fmt.aprintf("proc '%s' not found in graph", proc_name), true }
    defer _free_node(&node)

    callers := core.graph_get_callers(db, node.id)
    callees := core.graph_get_callees(db, node.id)
    defer { _free_nodes(callers[:]); delete(callers); _free_nodes(callees[:]); delete(callees) }

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    role       := node.memory_role if node.memory_role != "" else "neutral"
    violations := node.lint_violations if node.lint_violations != "" else "[]"
    fmt.sbprintf(&sb,
        `{"proc":{"name":%s,"file":%s,"line":%d,"memory_role":%s,"return_type":%s,"signature":%s,"lint_violations":%s}`,
        _gj(node.name), _gj(node.file), node.line, _gj(role),
        _gj(node.return_type), _gj(node.signature), violations)

    strings.write_string(&sb, `,"callers":[`)
    for n, idx in callers {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, "%s", _gj(n.name))
    }
    strings.write_string(&sb, `],"callees":[`)
    for n, idx in callees {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, "%s", _gj(n.name))
    }

    // Include allocator-typed package variables from the same file for context.
    allocator_vars := core.graph_find_file_allocator_vars(db, node.file)
    defer { _free_nodes(allocator_vars[:]); delete(allocator_vars) }
    strings.write_string(&sb, `],"allocator_vars":[`)
    for n, idx in allocator_vars {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, `{"name":%s,"line":%d}`, _gj(n.name), n.line)
    }
    strings.write_string(&sb, `]}`)
    return fmt.aprintf("%s", strings.to_string(sb)), false
}

// =============================================================================
// get_impact_radius
// =============================================================================

make_get_impact_radius_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "get_impact_radius",
            description = "Return all procedures transitively called by proc_name (what breaks if you change it).",
            input_schema = `{
                "type": "object",
                "properties": {
                    "proc_name": {"type": "string"},
                    "depth":     {"type": "integer", "description": "Max hops (default 3)"},
                    "db_path":   {"type": "string"}
                },
                "required": ["proc_name"]
            }`,
        },
        handler = _get_impact_radius_handler,
    }
}

@(private="file")
_get_impact_radius_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    proc_name, err := _extract_string_param(params, "proc_name")
    if err != "" { return err, true }
    depth   := _graph_opt_int(params, "depth", 3)
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    db, ok := core.graph_open(db_path)
    if !ok { return fmt.aprintf("graph db not found at %s", db_path), true }
    defer core.graph_close(db)

    node, found := core.graph_get_node(db, proc_name)
    if !found { return fmt.aprintf("proc '%s' not found in graph", proc_name), true }
    defer _free_node(&node)

    affected := core.graph_get_impact(db, node.id, depth)
    defer { _free_nodes(affected[:]); delete(affected) }

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    fmt.sbprintf(&sb, `{"proc":%s,"depth":%d,"affected":[`, _gj(proc_name), depth)
    for n, idx in affected {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, `{"name":%s,"file":%s,"line":%d,"kind":%s}`,
            _gj(n.name), _gj(n.file), n.line, _gj(n.kind))
    }
    strings.write_string(&sb, `]}`)
    return fmt.aprintf("%s", strings.to_string(sb)), false
}

// =============================================================================
// find_allocators
// =============================================================================

make_find_allocators_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "find_allocators",
            description = "Return all procedures tagged with memory_role='allocator' in the code graph.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "db_path": {"type": "string"}
                }
            }`,
        },
        handler = _find_allocators_handler,
    }
}

@(private="file")
_find_allocators_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    db, ok := core.graph_open(db_path)
    if !ok { return fmt.aprintf("graph db not found at %s — run --export-symbols first", db_path), true }
    defer core.graph_close(db)

    nodes := core.graph_find_allocators(db)
    defer { _free_nodes(nodes[:]); delete(nodes) }

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    strings.write_string(&sb, `{"allocators":[`)
    for n, idx in nodes {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, `{"name":%s,"file":%s,"line":%d}`, _gj(n.name), _gj(n.file), n.line)
    }
    strings.write_string(&sb, `]}`)
    return fmt.aprintf("%s", strings.to_string(sb)), false
}

// =============================================================================
// find_all_references
// =============================================================================

make_find_all_references_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "find_all_references",
            description = "Return every location in the codebase that references (calls) a named symbol. Foundation for rename refactoring.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "symbol":  {"type": "string", "description": "Symbol name to find references for"},
                    "db_path": {"type": "string"}
                },
                "required": ["symbol"]
            }`,
        },
        handler = _find_all_references_handler,
    }
}

@(private="file")
_find_all_references_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    symbol, err := _extract_string_param(params, "symbol")
    if err != "" { return err, true }
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    db, ok := core.graph_open(db_path)
    if !ok { return fmt.aprintf("graph db not found at %s", db_path), true }
    defer core.graph_close(db)

    refs := core.graph_find_all_references(db, symbol)
    defer {
        for r in refs { delete(r.source_name); delete(r.target_name); delete(r.kind); delete(r.file) }
        delete(refs)
    }

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    fmt.sbprintf(&sb, `{"symbol":%s,"reference_count":%d,"references":[`, _gj(symbol), len(refs))
    for r, idx in refs {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb, `{"caller":%s,"file":%s,"line":%d,"kind":%s}`,
            _gj(r.source_name), _gj(r.file), r.line, _gj(r.kind))
    }
    strings.write_string(&sb, `]}`)
    return fmt.aprintf("%s", strings.to_string(sb)), false
}

// =============================================================================
// run_lint_denoise
// =============================================================================

make_run_lint_denoise_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "run_lint_denoise",
            description = "Run all lint rules on an in-memory Odin source snippet and return structured fix objects for AI consumption. Use this in a fix-verify loop to converge toward 0 violations.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "source": {"type": "string", "description": "Odin source code to analyse"}
                },
                "required": ["source"]
            }`,
        },
        handler = _run_lint_denoise_handler,
    }
}

@(private="file")
_run_lint_denoise_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    source, err := _extract_string_param(params, "source")
    if err != "" { return err, true }

    collector := make([dynamic]core.Diagnostic)
    defer delete(collector)
    core.analyze_content("snippet.odin", source, &_ts_parser, &collector)

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    strings.write_string(&sb, `{"violations":[`)
    for d, idx in collector {
        if idx > 0 { strings.write_string(&sb, ",") }
        fmt.sbprintf(&sb,
            `{"rule":%s,"tier":%s,"line":%d,"column":%d,"message":%s,"fix":%s}`,
            _gj(d.rule_id), _gj(d.tier), d.line, d.column, _gj(d.message), _gj(d.fix))
    }
    fmt.sbprintf(&sb, `],"violation_count":%d}`, len(collector))
    return fmt.aprintf("%s", strings.to_string(sb)), false
}

// =============================================================================
// get_symbol — promoted from stub
// =============================================================================

make_get_symbol_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "get_symbol",
            description = "Look up a symbol by name in the code graph and return its location, kind, signature, and memory role.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "symbol":  {"type": "string"},
                    "db_path": {"type": "string"}
                },
                "required": ["symbol"]
            }`,
        },
        handler = _get_symbol_handler,
    }
}

@(private="file")
_get_symbol_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    symbol, err := _extract_string_param(params, "symbol")
    if err != "" { return err, true }
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    db, ok := core.graph_open(db_path)
    if !ok { return fmt.aprintf("graph db not found at %s — run --export-symbols first", db_path), true }
    defer core.graph_close(db)

    node, found := core.graph_get_node(db, symbol)
    if !found { return fmt.aprintf("symbol '%s' not found in graph", symbol), true }
    defer _free_node(&node)

    role       := node.memory_role if node.memory_role != "" else "neutral"
    violations := node.lint_violations if node.lint_violations != "" else "[]"
    return fmt.aprintf(
        `{"name":%s,"kind":%s,"file":%s,"line":%d,"signature":%s,"memory_role":%s,"lint_violations":%s}`,
        _gj(node.name), _gj(node.kind), _gj(node.file), node.line,
        _gj(node.signature), _gj(role), violations), false
}

// =============================================================================
// export_symbols — promoted from stub
// =============================================================================

make_export_symbols_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "export_symbols",
            description = "Run the DNA export pipeline on a path (file or directory) and write the code graph to SQLite + symbols.json.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path":    {"type": "string", "description": "File or directory to index"},
                    "db_path": {"type": "string", "description": "Output path for graph db"}
                },
                "required": ["path"]
            }`,
        },
        handler = _export_symbols_handler,
    }
}

@(private="file")
_export_symbols_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> (string, bool) {
    path, err := _extract_string_param(params, "path")
    if err != "" { return err, true }
    db_path := _graph_opt_string(params, "db_path", core.GRAPH_DB_PATH)

    targets := []string{path}
    r := core.export_symbols(targets, &_ts_parser, db_path)
    if !r.ok { return "export_symbols pipeline failed", true }

    return fmt.aprintf(
        `{"files_indexed":%d,"nodes":%d,"edges":%d,"unresolved":%d,"db_path":%s,"symbols_path":%s}`,
        r.files_indexed, r.nodes_written, r.edges_written, r.unresolved,
        _gj(r.db_path), _gj(r.symbols_path)), false
}

// =============================================================================
// Shared helpers (private to this file)
// =============================================================================

// _gj returns a JSON-quoted string. Separate from tool_lint.odin's _json_str
// to avoid the different signature clash.
@(private="file")
_gj :: proc(s: string) -> string {
    if !strings.contains_any(s, `"\`) { return fmt.tprintf(`"%s"`, s) }
    e1, _ := strings.replace_all(s,  `\`, `\\`)
    e2, _ := strings.replace_all(e1, `"`, `\"`)
    return fmt.tprintf(`"%s"`, e2)
}

@(private="file")
_graph_opt_string :: proc(params: json.Value, key: string, default_val: string) -> string {
    obj, ok := params.(json.Object)
    if !ok { return default_val }
    val, exists := obj[key]
    if !exists { return default_val }
    s, s_ok := val.(json.String)
    if !s_ok { return default_val }
    return string(s)
}

@(private="file")
_graph_opt_int :: proc(params: json.Value, key: string, default_val: int) -> int {
    obj, ok := params.(json.Object)
    if !ok { return default_val }
    val, exists := obj[key]
    if !exists { return default_val }
    f, f_ok := val.(json.Float)
    if !f_ok { return default_val }
    return int(f)
}

@(private="file")
_free_node :: proc(n: ^core.GraphNodeInfo) {
    delete(n.name); delete(n.kind); delete(n.file)
    delete(n.memory_role); delete(n.lint_violations); delete(n.signature); delete(n.return_type)
}

@(private="file")
_free_nodes :: proc(nodes: []core.GraphNodeInfo) {
    for n in nodes {
        delete(n.name); delete(n.kind); delete(n.file)
        delete(n.memory_role); delete(n.lint_violations); delete(n.signature)
    }
}
