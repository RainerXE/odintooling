/*
	odin-mcp — Reusable MCP Protocol Library
	File: vendor/odin-mcp/json_helpers.odin

	Minimal JSON building helpers used by the server and available to tool authors.
	All procs build into a strings.Builder on the provided allocator — no heap use.
*/
package mcp

import "base:runtime"
import "core:strings"
import "core:fmt"

// json_escape_string writes s as a JSON-quoted, escaped string into b.
// Handles the common escape sequences: \", \\, \n, \r, \t.
json_escape_string :: proc(b: ^strings.Builder, s: string) {
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

// rpcid_to_json writes the JSON representation of id into b.
// Absent id (zero union) → "null".
rpcid_to_json :: proc(b: ^strings.Builder, id: RPCID) {
	switch v in id {
	case i64:
		fmt.sbprint(b, v)
	case string:
		json_escape_string(b, v)
	case:
		strings.write_string(b, "null")
	}
}

// build_success_response wraps a pre-serialised result JSON fragment in the
// JSON-RPC 2.0 success envelope.
// result must be valid JSON (object, array, string, number, bool, or null).
build_success_response :: proc(id: RPCID, result: string, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	rpcid_to_json(&b, id)
	strings.write_string(&b, `,"result":`)
	strings.write_string(&b, result)
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

// build_error_response builds a JSON-RPC 2.0 error envelope.
build_error_response :: proc(id: RPCID, code: int, message: string, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	rpcid_to_json(&b, id)
	strings.write_string(&b, `,"error":{"code":`)
	fmt.sbprint(&b, code)
	strings.write_string(&b, `,"message":`)
	json_escape_string(&b, message)
	strings.write_string(&b, `}}`)
	return strings.to_string(b)
}

// build_tool_result wraps a tool handler's return value in a MCP CallToolResult.
// is_error=true → the content text is treated as an error by the client.
build_tool_result :: proc(id: RPCID, content: string, is_error: bool, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, `{"jsonrpc":"2.0","id":`)
	rpcid_to_json(&b, id)
	strings.write_string(&b, `,"result":{"content":[{"type":"text","text":`)
	json_escape_string(&b, content)
	strings.write_string(&b, `}],"isError":`)
	strings.write_string(&b, "true" if is_error else "false")
	strings.write_string(&b, `}}`)
	return strings.to_string(b)
}
