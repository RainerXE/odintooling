/*
	odin-mcp — Reusable MCP Protocol Library
	File: vendor/odin-mcp/server.odin

	MCP server dispatch loop and method handlers.
	Call server_init, register tools with server_register_tool,
	then call server_run which blocks until stdin EOF.
*/
package mcp

import "core:bufio"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

// BUFIO_SIZE is the internal read buffer for stdin.
// 64 KiB is enough for any realistic MCP message.
BUFIO_SIZE :: 64 * 1024

// server_init prepares s for use. Call once before registering tools.
server_init :: proc(s: ^MCPServer, name: string, version: string) {
	s.name    = name
	s.version = version
	s.tools   = make([dynamic]RegisteredTool)
}

// server_register_tool appends one tool to the dispatch table.
// Call any number of times before server_run.
server_register_tool :: proc(s: ^MCPServer, tool: RegisteredTool) {
	append(&s.tools, tool)
}

// server_run enters the read/dispatch/write loop.
// Blocks until stdin EOF or unrecoverable I/O error.
// All request-scoped memory is allocated on context.temp_allocator
// and freed at the end of each iteration.
server_run :: proc(s: ^MCPServer) {
	buf := make([]u8, BUFIO_SIZE)
	defer delete(buf)

	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, os.to_reader(os.stdin), buf)
	defer bufio.reader_destroy(&reader)

	for {
		// All per-request allocations live on the temp allocator.
		defer free_all(context.temp_allocator)

		// 1. Read framed bytes.
		raw, ok := read_message(&reader, context.temp_allocator)
		if !ok {
			break // EOF or framing error — clean exit
		}

		// 2. Parse JSON.
		val, parse_err := json.parse(raw, allocator = context.temp_allocator)
		if parse_err != nil {
			write_string_message(build_error_response({}, ERR_PARSE_ERROR, "JSON parse error", context.temp_allocator))
			continue
		}

		// 3. Extract envelope fields.
		req, extract_ok := _extract_request(val)
		if !extract_ok {
			write_string_message(build_error_response({}, ERR_INVALID_REQUEST, "invalid JSON-RPC request", context.temp_allocator))
			continue
		}

		// 4. Dispatch.
		resp, has_resp := _dispatch(s, req)

		// 5. Write response only for requests (notifications have no id).
		if has_resp {
			write_string_message(resp)
		}
	}
}

// ── Internal helpers ──────────────────────────────────────────────────────────

@(private="file")
_extract_request :: proc(val: json.Value) -> (req: MCPRequest, ok: bool) {
	obj, is_obj := val.(json.Object)
	if !is_obj { return {}, false }

	method_val, has_method := obj["method"]
	if !has_method { return {}, false }
	method_str, is_str := method_val.(json.String)
	if !is_str { return {}, false }

	req.method = string(method_str)
	req.params  = obj["params"] if "params" in obj else json.Null{}

	// Extract id — absent for notifications.
	if id_val, has_id := obj["id"]; has_id {
		switch v in id_val {
		case json.Integer: req.id = i64(v)
		case json.Float:   req.id = i64(v)
		case json.String:  req.id = string(v)
		case json.Null, json.Boolean, json.Array, json.Object:
			// null / unexpected type: treat as notification (no id)
		}
	}

	return req, true
}

@(private="file")
_dispatch :: proc(s: ^MCPServer, req: MCPRequest) -> (resp: string, has_resp: bool) {
	// Notifications (no id) get no response — but we still process them.
	is_notification := req.id == nil

	switch req.method {
	case "initialize":
		resp = _handle_initialize(s, req.id)
		return resp, true

	case "initialized":
		return "", false // notification — no response

	case "ping":
		if is_notification { return "", false }
		resp = build_success_response(req.id, `{}`, context.temp_allocator)
		return resp, true

	case "tools/list":
		if is_notification { return "", false }
		resp = _handle_tools_list(s, req.id)
		return resp, true

	case "tools/call":
		if is_notification { return "", false }
		resp = _handle_tools_call(s, req.id, req.params)
		return resp, true

	case:
		if is_notification { return "", false }
		resp = build_error_response(req.id, ERR_METHOD_NOT_FOUND,
			fmt.tprintf("method not found: %s", req.method), context.temp_allocator)
		return resp, true
	}
}

@(private="file")
_handle_initialize :: proc(s: ^MCPServer, id: RPCID) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"protocolVersion":"`)
	strings.write_string(&b, MCP_PROTOCOL_VERSION)
	strings.write_string(&b, `","capabilities":{"tools":{}},"serverInfo":{"name":`)
	json_escape_string(&b, s.name)
	strings.write_string(&b, `,"version":`)
	json_escape_string(&b, s.version)
	strings.write_string(&b, `}}`)
	return build_success_response(id, strings.to_string(b), context.temp_allocator)
}

@(private="file")
_handle_tools_list :: proc(s: ^MCPServer, id: RPCID) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"tools":[`)
	for tool, i in s.tools {
		if i > 0 { strings.write_byte(&b, ',') }
		strings.write_string(&b, `{"name":`)
		json_escape_string(&b, tool.defn.name)
		strings.write_string(&b, `,"description":`)
		json_escape_string(&b, tool.defn.description)
		strings.write_string(&b, `,"inputSchema":`)
		strings.write_string(&b, tool.defn.input_schema)
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, `]}`)
	return build_success_response(id, strings.to_string(b), context.temp_allocator)
}

@(private="file")
_handle_tools_call :: proc(s: ^MCPServer, id: RPCID, params: json.Value) -> string {
	// Extract tool name from params.name
	params_obj, is_obj := params.(json.Object)
	if !is_obj {
		return build_error_response(id, ERR_INVALID_PARAMS, "params must be an object", context.temp_allocator)
	}

	name_val, has_name := params_obj["name"]
	if !has_name {
		return build_error_response(id, ERR_INVALID_PARAMS, "missing 'name' in params", context.temp_allocator)
	}
	tool_name, is_str := name_val.(json.String)
	if !is_str {
		return build_error_response(id, ERR_INVALID_PARAMS, "'name' must be a string", context.temp_allocator)
	}

	// Extract arguments (may be absent).
	arguments: json.Value = json.Null{}
	if args_val, has_args := params_obj["arguments"]; has_args {
		arguments = args_val
	}

	// Find and call the handler.
	for tool in s.tools {
		if tool.defn.name == string(tool_name) {
			result, is_error := tool.handler(arguments, context.temp_allocator)
			return build_tool_result(id, result, is_error, context.temp_allocator)
		}
	}

	return build_error_response(id, ERR_METHOD_NOT_FOUND,
		fmt.tprintf("unknown tool: %s", tool_name), context.temp_allocator)
}
