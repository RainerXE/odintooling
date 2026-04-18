/*
	odin-mcp — Reusable MCP Protocol Library
	File: vendor/odin-mcp/types.odin

	All wire types for the MCP stdio transport (JSON-RPC 2.0).
	This package has no dependency on odin-lint or any project-specific code.
	Any Odin project can import vendor/odin-mcp to build an MCP server.
*/
package mcp

import "core:encoding/json"
import "base:runtime"

// ── JSON-RPC 2.0 ID ───────────────────────────────────────────────────────────

// RPCID is the JSON-RPC 2.0 request id: integer, string, or absent (notification).
// Absent is represented as the zero value (no active union tag).
RPCID :: union { i64, string }

// ── Incoming message ──────────────────────────────────────────────────────────

// MCPRequest holds one parsed JSON-RPC request or notification from the client.
// params is owned by the request; the server calls json.destroy_value on it
// after the handler returns.
MCPRequest :: struct {
	id:     RPCID,       // absent (zero) for notifications
	method: string,      // e.g. "tools/call"
	params: json.Value,  // raw params — may be json.Null if omitted
}

// ── Tool registry ─────────────────────────────────────────────────────────────

// ToolHandler is the proc signature every tool must implement.
//   params    — the raw json.Value of the "arguments" field inside "params".
//               Do NOT call json.destroy_value on it; the server owns it.
//   allocator — temp allocator scoped to this request; use it freely.
//   result    — serialised JSON string to embed in the CallToolResult.
//   is_error  — true → result is an error message, not a successful payload.
ToolHandler :: #type proc(params: json.Value, allocator: runtime.Allocator) -> (result: string, is_error: bool)

// ToolDefinition describes one tool for the tools/list response.
ToolDefinition :: struct {
	name:         string,
	description:  string,
	input_schema: string,  // verbatim JSON Schema object, e.g. `{"type":"object",...}`
}

// RegisteredTool pairs a definition with its handler.
RegisteredTool :: struct {
	defn:    ToolDefinition,
	handler: ToolHandler,
}

// ── Server ────────────────────────────────────────────────────────────────────

// MCPServer holds server identity and the tool dispatch table.
// Initialise with server_init, populate with server_register_tool,
// then call server_run which blocks until stdin EOF.
MCPServer :: struct {
	name:    string,
	version: string,
	tools:   [dynamic]RegisteredTool,
}

// ── Standard JSON-RPC 2.0 error codes ────────────────────────────────────────

ERR_PARSE_ERROR      :: -32700
ERR_INVALID_REQUEST  :: -32600
ERR_METHOD_NOT_FOUND :: -32601
ERR_INVALID_PARAMS   :: -32602
ERR_INTERNAL_ERROR   :: -32603

// MCP protocol version this library targets.
MCP_PROTOCOL_VERSION :: "2024-11-05"
