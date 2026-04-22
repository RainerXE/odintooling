/*
	odin-lint OLS Plugin Entry Point
	File: src/core/plugin_main.odin

	Implements the OLS plugin interface (see vendor/ols/src/server/plugin.odin
	and plans/plugin-interface-spec.md) for use as a shared library (.dylib/.so/.dll).

	Build:
	    ./scripts/build_plugin.sh  →  artifacts/odin-lint-plugin.dylib

	ols.json registration:
	    {
	      "plugins": [
	        { "name": "odin-lint", "path": "/path/to/artifacts/odin-lint-plugin.dylib", "enabled": true }
	      ]
	    }

	Design notes:
	  - Reuses all existing rule matchers (c001–c012) from this package.
	  - Uses in-memory document text from OLS (not disk) so unsaved changes are linted.
	  - Tree-sitter parser is initialised once in init() and reused across calls.
	  - All result memory is heap-allocated; OLS calls free_result when done.
	  - Every "c" calling-convention proc pushes a default Odin context at entry.
*/
package core

import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"


// ── OLS Plugin interface types ────────────────────────────────────────────────
//
// These must exactly match the types defined in:
//   vendor/ols/src/server/plugin.odin
//
// They are duplicated here so the plugin can be compiled independently of OLS.
// Kept in sync with OLS_PLUGIN_API_VERSION "1.0".

OLSPluginCapability :: enum u32 {
	Diagnostics   = 0,
	CodeActions   = 1,
	Hover         = 2,
	Completions   = 3,
	Format        = 4,
	Rename        = 5,
	CallHierarchy = 6,
}
OLSPluginCapabilities :: bit_set[OLSPluginCapability;u32]

OLSPluginPosition :: struct #packed {
	line:      i32,
	character: i32,
}
OLSPluginRange :: struct #packed {
	start: OLSPluginPosition,
	end:   OLSPluginPosition,
}
OLSPluginSeverity :: enum i32 {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}
OLSPluginDocument :: struct #packed {
	uri:      cstring,
	path:     cstring,
	text:     [^]u8,
	text_len: i32,
	ast:      rawptr,
}
OLSPluginDiagnostic :: struct #packed {
	range:    OLSPluginRange,
	severity: OLSPluginSeverity,
	code:     cstring,
	source:   cstring,
	message:  cstring,
	has_fix:  bool,
	fix_hint: cstring,
}
OLSPluginDiagnosticList :: struct #packed {
	items: [^]OLSPluginDiagnostic,
	count: i32,
}
OLSPluginTextEdit :: struct #packed {
	range:    OLSPluginRange,
	new_text: cstring,
}
OLSPluginCodeAction :: struct #packed {
	title:        cstring,
	kind:         cstring,
	is_preferred: bool,
	edit:         OLSPluginTextEdit,
}
OLSPluginCodeActionList :: struct #packed {
	items: [^]OLSPluginCodeAction,
	count: i32,
}

// OLSPluginCallHierarchyCall mirrors OLSCallHierarchyCall in plugin.odin.
// Used for all 3 call hierarchy hooks (prepare, incoming, outgoing).
// call_site_line = -1 when not applicable (prepare results).
OLSPluginCallHierarchyCall :: struct #packed {
	name:           cstring,
	uri:            cstring,
	line:           i32,
	character:      i32,
	call_site_line: i32,
}
OLSPluginCallHierarchyCallList :: struct #packed {
	items: [^]OLSPluginCallHierarchyCall,
	count: i32,
}

// OLSPluginDescriptor mirrors OLSPlugin in vendor/ols/src/server/plugin.odin.
OLSPluginDescriptor :: struct {
	name:            cstring,
	version:         cstring,
	capabilities:    OLSPluginCapabilities,
	init:            proc "c" (host_api_version: cstring) -> bool,
	shutdown:        proc "c" (),
	on_diagnostics:  proc "c" (doc: ^OLSPluginDocument) -> ^OLSPluginDiagnosticList,
	on_code_actions: proc "c" (doc: ^OLSPluginDocument, range: OLSPluginRange) -> ^OLSPluginCodeActionList,
	on_hover:        proc "c" (doc: ^OLSPluginDocument, pos: OLSPluginPosition) -> cstring,
	on_rename:       proc "c" (doc: ^OLSPluginDocument, pos: OLSPluginPosition, new_name: cstring) -> ^OLSPluginCodeActionList,
	on_prepare_call_hierarchy: proc "c" (doc: ^OLSPluginDocument, line: i32, char: i32) -> ^OLSPluginCallHierarchyCallList,
	on_incoming_calls:         proc "c" (name: cstring, uri: cstring) -> ^OLSPluginCallHierarchyCallList,
	on_outgoing_calls:         proc "c" (name: cstring, uri: cstring) -> ^OLSPluginCallHierarchyCallList,
	free_result:               proc "c" (ptr: rawptr),
	free_call_hierarchy:       proc "c" (ptr: rawptr),
}


// ── Plugin state ──────────────────────────────────────────────────────────────

@(private = "file")
_plugin: OLSPluginDescriptor = {
	name         = "odin-lint",
	version      = "0.1.0",
	capabilities = {.Diagnostics, .CallHierarchy},
	init         = _ols_init,
	shutdown     = _ols_shutdown,
	on_diagnostics             = _ols_on_diagnostics,
	on_code_actions            = _ols_on_code_actions,
	on_hover                   = nil,
	on_rename                  = nil,
	on_prepare_call_hierarchy  = _ols_prepare_call_hierarchy,
	on_incoming_calls          = _ols_incoming_calls,
	on_outgoing_calls          = _ols_outgoing_calls,
	free_result                = _ols_free_result,
	free_call_hierarchy        = _ols_free_call_hierarchy,
}

@(private = "file")
_ts_parser: TreeSitterASTParser

@(private = "file")
_ts_ready: bool


// ── Entry point ───────────────────────────────────────────────────────────────

// ols_plugin_get is called by OLS immediately after dynlib.load_library.
// Returns the plugin descriptor; nil causes OLS to unload the library.
@(export)
ols_plugin_get :: proc "c" () -> ^OLSPluginDescriptor {
	return &_plugin
}


// ── Lifecycle ─────────────────────────────────────────────────────────────────

@(private = "file")
_ols_init :: proc "c" (host_api_version: cstring) -> bool {
	context = runtime.default_context()
	if string(host_api_version) != "1.0" {
		return false
	}
	p, ok := initTreeSitterParser()
	if !ok {
		return false
	}
	_ts_parser = p
	_ts_ready  = true
	return true
}

@(private = "file")
_ols_shutdown :: proc "c" () {
	context = runtime.default_context()
	if _ts_ready {
		deinitTreeSitterParser(_ts_parser)
		_ts_ready = false
	}
}


// ── on_diagnostics ─────────────────────────────────────────────────────────────

// _ols_on_diagnostics is the merge-all diagnostic hook.
// Called by OLS after every file open and save.
// Returns nil when there are no diagnostics for this document.
@(private = "file")
_ols_on_diagnostics :: proc "c" (doc: ^OLSPluginDocument) -> ^OLSPluginDiagnosticList {
	context = runtime.default_context()
	if !_ts_ready || doc == nil {
		return nil
	}

	file_path := string(doc.path)

	// Only process Odin source files.
	if !strings.has_suffix(file_path, ".odin") {
		return nil
	}

	// Use the in-memory text provided by OLS (includes unsaved edits).
	// Fall back to disk only when the editor hasn't provided text.
	content: string
	if doc.text != nil && doc.text_len > 0 {
		content = string(doc.text[:doc.text_len])
	} else {
		return nil // No content available; skip.
	}

	diags := make([dynamic]Diagnostic, 0, 16)
	defer delete(diags)

	_plugin_run_rules(file_path, content, &diags)

	if len(diags) == 0 {
		return nil
	}
	return _diags_to_ols_list(diags[:])
}

// _plugin_run_rules delegates to analyze_content (src/core/analyze_content.odin).
@(private = "file")
_plugin_run_rules :: proc(file_path: string, content: string, diags: ^[dynamic]Diagnostic) {
	analyze_content(file_path, content, &_ts_parser, diags)
}


// ── on_code_actions ────────────────────────────────────────────────────────────

// _ols_on_code_actions is reserved for M5.5 (autofix integration).
@(private = "file")
_ols_on_code_actions :: proc "c" (
	doc:   ^OLSPluginDocument,
	range: OLSPluginRange,
) -> ^OLSPluginCodeActionList {
	return nil
}


// ── Call hierarchy ─────────────────────────────────────────────────────────────

// _ols_prepare_call_hierarchy extracts the identifier at (line, char) in the
// document and looks it up in the code graph. Returns nil when no graph exists
// or no proc is found at that position.
@(private = "file")
_ols_prepare_call_hierarchy :: proc "c" (
	doc:  ^OLSPluginDocument,
	line: i32,
	char: i32,
) -> ^OLSPluginCallHierarchyCallList {
	context = runtime.default_context()
	if doc == nil { return nil }

	text := string(doc.text[:doc.text_len]) if doc.text != nil && doc.text_len > 0 else ""
	if len(text) == 0 { return nil }

	word := _word_at(text, int(line), int(char))
	if len(word) == 0 { return nil }

	db_path := _graph_db_path_for(string(doc.path))
	db, ok := graph_open(db_path)
	if !ok { return nil }
	defer graph_close(db)

	info, info_ok := graph_get_node(db, word)
	if !info_ok { return nil }
	defer graph_free_node_info(info)

	ha      := runtime.heap_allocator()
	uri_str := _file_uri(info.file)

	item_raw, err1 := mem.alloc(size_of(OLSPluginCallHierarchyCall), align_of(OLSPluginCallHierarchyCall), ha)
	if err1 != nil { delete(uri_str); return nil }
	item := cast(^OLSPluginCallHierarchyCall)item_raw
	item.name           = strings.clone_to_cstring(info.name, ha)
	item.uri            = strings.clone_to_cstring(uri_str, ha)
	item.line           = i32(max(info.line - 1, 0))
	item.character      = 0
	item.call_site_line = -1
	delete(uri_str)

	list_raw, err2 := mem.alloc(size_of(OLSPluginCallHierarchyCallList), align_of(OLSPluginCallHierarchyCallList), ha)
	if err2 != nil {
		mem.free(item_raw, ha)
		return nil
	}
	list := cast(^OLSPluginCallHierarchyCallList)list_raw
	list.items = cast([^]OLSPluginCallHierarchyCall)item_raw
	list.count = 1
	return list
}

// _ols_incoming_calls returns all callers of the named proc from the code graph.
@(private = "file")
_ols_incoming_calls :: proc "c" (name: cstring, uri: cstring) -> ^OLSPluginCallHierarchyCallList {
	context = runtime.default_context()
	if name == nil { return nil }

	db_path := _graph_db_path_for(_uri_to_path(string(uri)))
	db, ok := graph_open(db_path)
	if !ok { return nil }
	defer graph_close(db)

	node_id := graph_find_node(db, string(name))
	if node_id < 0 { return nil }

	callers := graph_get_callers(db, node_id)
	defer { for n in callers { graph_free_node_info(n) }; delete(callers) }

	return _build_call_list(callers[:])
}

// _ols_outgoing_calls returns all callees of the named proc from the code graph.
@(private = "file")
_ols_outgoing_calls :: proc "c" (name: cstring, uri: cstring) -> ^OLSPluginCallHierarchyCallList {
	context = runtime.default_context()
	if name == nil { return nil }

	db_path := _graph_db_path_for(_uri_to_path(string(uri)))
	db, ok := graph_open(db_path)
	if !ok { return nil }
	defer graph_close(db)

	node_id := graph_find_node(db, string(name))
	if node_id < 0 { return nil }

	callees := graph_get_callees(db, node_id)
	defer { for n in callees { graph_free_node_info(n) }; delete(callees) }

	return _build_call_list(callees[:])
}

@(private = "file")
_build_call_list :: proc(nodes: []GraphNodeInfo) -> ^OLSPluginCallHierarchyCallList {
	ha := runtime.heap_allocator()
	n  := len(nodes)
	if n == 0 { return nil }

	items_raw, err1 := mem.alloc(size_of(OLSPluginCallHierarchyCall) * n, align_of(OLSPluginCallHierarchyCall), ha)
	if err1 != nil { return nil }
	items := cast([^]OLSPluginCallHierarchyCall)items_raw

	for node, i in nodes {
		uri_str := _file_uri(node.file)
		items[i] = OLSPluginCallHierarchyCall {
			name           = strings.clone_to_cstring(node.name, ha),
			uri            = strings.clone_to_cstring(uri_str, ha),
			line           = i32(max(node.line - 1, 0)),
			character      = 0,
			call_site_line = -1,
		}
		delete(uri_str)
	}

	list_raw, err2 := mem.alloc(size_of(OLSPluginCallHierarchyCallList), align_of(OLSPluginCallHierarchyCallList), ha)
	if err2 != nil {
		mem.free(items_raw, ha)
		return nil
	}
	list := cast(^OLSPluginCallHierarchyCallList)list_raw
	list.items = items
	list.count = i32(n)
	return list
}

// _word_at extracts the Odin identifier at (line, col) in text (0-indexed).
@(private = "file")
_word_at :: proc(text: string, line, col: int) -> string {
	// Find line start offset.
	cur_line := 0
	i := 0
	for i < len(text) && cur_line < line {
		if text[i] == '\n' { cur_line += 1 }
		i += 1
	}
	if cur_line < line { return "" }
	line_start := i
	// Find end of line.
	line_end := line_start
	for line_end < len(text) && text[line_end] != '\n' && text[line_end] != '\r' {
		line_end += 1
	}
	line_text := text[line_start:line_end]
	if col >= len(line_text) { return "" }
	// Scan backward for word start.
	start := col
	for start > 0 && _is_ident(rune(line_text[start-1])) { start -= 1 }
	// Scan forward for word end.
	end := col
	for end < len(line_text) && _is_ident(rune(line_text[end])) { end += 1 }
	if end <= start { return "" }
	return line_text[start:end]
}

@(private = "file")
_is_ident :: proc(r: rune) -> bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_'
}

// _graph_db_path_for returns the graph DB path by walking up from file_path
// looking for .codegraph/odin_lint_graph.db.  Falls back to GRAPH_DB_PATH (cwd-relative).
@(private = "file")
_graph_db_path_for :: proc(file_path: string) -> string {
	// Find the last separator to get the directory.
	dir_end := len(file_path)
	for dir_end > 0 && file_path[dir_end-1] != '/' && file_path[dir_end-1] != '\\' {
		dir_end -= 1
	}
	dir := file_path[:dir_end]
	for len(dir) > 1 {
		candidate := strings.concatenate({dir, "/", GRAPH_DB_PATH})
		if os.is_file(candidate) { return candidate }
		delete(candidate)
		// Go up one level.
		new_end := len(dir) - 1
		for new_end > 0 && dir[new_end-1] != '/' && dir[new_end-1] != '\\' {
			new_end -= 1
		}
		if new_end >= len(dir) { break }
		dir = dir[:new_end]
	}
	return GRAPH_DB_PATH
}

// _file_uri converts a file path to a "file://..." URI string.
// Absolute paths produce "file:///abs/path"; relative paths produce "file://rel/path".
@(private = "file")
_file_uri :: proc(path: string) -> string {
	if len(path) > 0 && path[0] == '/' {
		return strings.concatenate({"file://", path})
	}
	return strings.concatenate({"file://", path})
}

// _uri_to_path strips the "file://" prefix from a file URI.
@(private = "file")
_uri_to_path :: proc(uri: string) -> string {
	if strings.has_prefix(uri, "file:///") { return uri[len("file://"):] }
	if strings.has_prefix(uri, "file://")  { return uri[len("file://"):] }
	return uri
}


// ── Memory management ──────────────────────────────────────────────────────────

// _ols_free_call_hierarchy frees an OLSPluginCallHierarchyCallList.
// All 3 call hierarchy handlers (prepare, incoming, outgoing) return this type.
@(private = "file")
_ols_free_call_hierarchy :: proc "c" (ptr: rawptr) {
	context = runtime.default_context()
	if ptr == nil { return }
	ha   := runtime.heap_allocator()
	list := cast(^OLSPluginCallHierarchyCallList)ptr
	if list.items != nil {
		for i in 0..<int(list.count) {
			item := list.items[i]
			if item.name != nil { mem.free(rawptr(item.name), ha) }
			if item.uri  != nil { mem.free(rawptr(item.uri),  ha) }
		}
		mem.free(rawptr(list.items), ha)
	}
	mem.free(ptr, ha)
}

// _ols_free_result is called by OLS when it is done with a result list.
// ptr must be the ^OLSPluginDiagnosticList pointer returned by on_diagnostics.
// Frees the list struct, the items array, and all heap-allocated message strings.
@(private = "file")
_ols_free_result :: proc "c" (ptr: rawptr) {
	context = runtime.default_context()
	if ptr == nil {
		return
	}
	ha   := runtime.heap_allocator()
	list := cast(^OLSPluginDiagnosticList)ptr
	if list.items != nil {
		for i in 0 ..< int(list.count) {
			item := list.items[i]
			// message and fix_hint were clone_to_cstring-allocated on the heap.
			if item.message != nil {
				mem.free(rawptr(item.message), ha)
			}
			if item.has_fix && item.fix_hint != nil {
				mem.free(rawptr(item.fix_hint), ha)
			}
		}
		mem.free(rawptr(list.items), ha)
	}
	mem.free(ptr, ha)
}

// _diags_to_ols_list converts internal Diagnostics to a heap-allocated
// OLSPluginDiagnosticList. OLS takes ownership and calls free_result when done.
@(private = "file")
_diags_to_ols_list :: proc(diags: []Diagnostic) -> ^OLSPluginDiagnosticList {
	ha := runtime.heap_allocator()
	n  := len(diags)

	items_raw, alloc_err := mem.alloc(size_of(OLSPluginDiagnostic) * n, align_of(OLSPluginDiagnostic), ha)
	if alloc_err != nil || items_raw == nil {
		return nil
	}
	items := cast([^]OLSPluginDiagnostic)items_raw

	for d, i in diags {
		sev := OLSPluginSeverity.Warning
		if d.tier == "correctness" || d.tier == "error" {
			sev = .Error
		}

		// line/column in our Diagnostic are 1-based; LSP expects 0-based.
		line := max(d.line - 1, 0)
		col  := max(d.column - 1, 0)

		// Heap-allocate the message (freed by _ols_free_result).
		msg_cstr := strings.clone_to_cstring(d.message, ha)

		var_hint: cstring = nil
		if d.has_fix {
			var_hint = strings.clone_to_cstring(d.fix, ha)
		}

		items[i] = OLSPluginDiagnostic {
			range = OLSPluginRange {
				start = OLSPluginPosition{line = i32(line), character = i32(col)},
				end   = OLSPluginPosition{line = i32(line), character = i32(col + 1)},
			},
			severity = sev,
			code     = strings.clone_to_cstring(d.rule_id, ha),
			source   = "odin-lint",
			message  = msg_cstr,
			has_fix  = d.has_fix,
			fix_hint = var_hint,
		}
	}

	list_raw, list_err := mem.alloc(size_of(OLSPluginDiagnosticList), align_of(OLSPluginDiagnosticList), ha)
	if list_err != nil || list_raw == nil {
		mem.free(items_raw, ha)
		return nil
	}
	list := cast(^OLSPluginDiagnosticList)list_raw
	list.items = items
	list.count = i32(n)
	return list
}
