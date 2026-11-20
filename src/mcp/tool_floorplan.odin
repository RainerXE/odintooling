// mcp/tool_floorplan.odin — MCP access to the self-contained graph map.
//
// get_floorplan_data returns the same JSON dataset as `olt floorplan --json`.
// generate_floorplan writes the embedded HTML map and returns its path/summary.
// Neither tool exports the graph; call export_symbols first when it is missing.
package mcp_server

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

import mcp  "../../vendor/odin-mcp/mcp"
import core "../core"

// =============================================================================
// get_floorplan_data
// =============================================================================

make_get_floorplan_data_tool :: proc() -> mcp.Tool {
    return mcp.Tool{
        defn = mcp.ToolDefinition{
            name        = "get_floorplan_data",
            description = "Return the same JSON dataset as `olt floorplan --json`: project metadata, packages, files, nodes, edges, imports, unresolved calls, findings and summary. Read-only; does not write HTML. Requires an existing graph (call export_symbols first).",
            input_schema = `{
                "type": "object",
                "properties": {
                    "db_path": {
                        "type": "string",
                        "description": "Graph database path (default: .codegraph/olt.db, then .codegraph/codegraph.db)"
                    },
                    "title": {
                        "type": "string",
                        "description": "Project name shown in the map data (default: graph project directory name)"
                    }
                }
            }`,
        },
        simple_handler = _get_floorplan_data_handler,
    }
}

@(private="file")
_get_floorplan_data_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> mcp.Tool_Result {
    db_path := _fp_opt_string(params, "db_path", "")
    title   := _fp_opt_string(params, "title", "")

    result := core.floorplan_generate(db_path, "", title, false)
    if !result.ok { return _floorplan_error(result, allocator) }

    return mcp.tool_ok(strings.clone(result.data_json, allocator), allocator)
}

// =============================================================================
// generate_floorplan
// =============================================================================

make_generate_floorplan_tool :: proc() -> mcp.Tool {
    return mcp.Tool{
        defn = mcp.ToolDefinition{
            name        = "generate_floorplan",
            description = "Write the self-contained HTML map from an existing code graph and return its path, byte size, summary and stale-file marker. Does not open a browser and does not export the graph; call export_symbols first when needed.",
            input_schema = `{
                "type": "object",
                "properties": {
                    "db_path": {
                        "type": "string",
                        "description": "Graph database path (default: .codegraph/olt.db, then .codegraph/codegraph.db)"
                    },
                    "out_path": {
                        "type": "string",
                        "description": "Output HTML path (default: .codegraph/floorplan.html)"
                    },
                    "title": {
                        "type": "string",
                        "description": "Map title (default: graph project directory name)"
                    }
                }
            }`,
        },
        simple_handler = _generate_floorplan_handler,
    }
}

@(private="file")
_generate_floorplan_handler :: proc(params: json.Value, allocator: runtime.Allocator) -> mcp.Tool_Result {
    db_path  := _fp_opt_string(params, "db_path", "")
    out_path := _fp_opt_string(params, "out_path", "")
    title    := _fp_opt_string(params, "title", "")

    result := core.floorplan_generate(db_path, out_path, title, true)
    if !result.ok { return _floorplan_error(result, allocator) }

    absolute_path := result.out_path
    if abs, abs_err := os.get_absolute_path(result.out_path, allocator); abs_err == nil {
        absolute_path = abs
    }

    b := strings.builder_make(allocator)
    strings.write_string(&b, `{"ok":true,"path":`)
    _json_str(&b, absolute_path)
    fmt.sbprintf(&b,
        `,"bytes":%d,"schema_version":%d,"summary":{{"files":%d,"packages":%d,"symbols":%d,"edges":%d,"unresolved":%d,"findings":%d}},"stale_file":`,
        result.bytes, core.FLOORPLAN_SCHEMA_VERSION,
        result.files, result.packages, result.symbols, result.edges, result.unresolved, result.findings)
    _json_str(&b, result.stale_file)
    strings.write_byte(&b, '}')
    return mcp.tool_ok(strings.to_string(b), allocator)
}

@(private="file")
_floorplan_error :: proc(result: core.FloorplanResult, allocator: runtime.Allocator) -> mcp.Tool_Result {
    kind := mcp.Tool_Error_Kind.Internal
    if result.not_found { kind = .Not_Found }
    return mcp.tool_error(kind, fmt.aprintf("%s", result.error, allocator = allocator), allocator)
}

@(private="file")
_fp_opt_string :: proc(params: json.Value, key: string, default_val: string) -> string {
    obj, ok := params.(json.Object)
    if !ok { return default_val }
    val, exists := obj[key]
    if !exists { return default_val }
    s, s_ok := val.(json.String)
    if !s_ok { return default_val }
    return string(s)
}
