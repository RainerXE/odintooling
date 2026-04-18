package mcp_server

import "core:encoding/json"
import "base:runtime"

import mcp "../../vendor/odin-mcp"

// ── Tier 2 stubs — full implementation in M5.6 ───────────────────────────────

make_get_symbol_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "get_symbol",
            description = "Get definition, type, and signature for a symbol (requires OLS — not yet implemented, coming in M5.6).",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path":   {"type": "string", "description": "Absolute path to the .odin file"},
                    "symbol": {"type": "string", "description": "Symbol name to look up"}
                },
                "required": ["path", "symbol"]
            }`,
        },
        handler = _stub_handler,
    }
}

make_export_symbols_tool :: proc() -> mcp.RegisteredTool {
    return mcp.RegisteredTool{
        defn = mcp.ToolDefinition{
            name        = "export_symbols",
            description = "Export a symbols.json call graph for a file or package (not yet implemented, coming in M5.6).",
            input_schema = `{
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to file or directory"}
                },
                "required": ["path"]
            }`,
        },
        handler = _stub_handler,
    }
}

@(private="file")
_stub_handler :: proc(_params: json.Value, _allocator: runtime.Allocator) -> (string, bool) {
    return "not yet implemented — coming in M5.6", true
}
