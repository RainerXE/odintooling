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
import "core:strings"


// ── OLS Plugin interface types ────────────────────────────────────────────────
//
// These must exactly match the types defined in:
//   vendor/ols/src/server/plugin.odin
//
// They are duplicated here so the plugin can be compiled independently of OLS.
// Kept in sync with OLS_PLUGIN_API_VERSION "1.0".

OLSPluginCapability :: enum u32 {
	Diagnostics = 0,
	CodeActions  = 1,
	Hover        = 2,
	Completions  = 3,
	Format       = 4,
	Rename       = 5,
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
	free_result:     proc "c" (ptr: rawptr),
}


// ── Plugin state ──────────────────────────────────────────────────────────────

@(private = "file")
_plugin: OLSPluginDescriptor = {
	name         = "odin-lint",
	version      = "0.1.0",
	capabilities = {.Diagnostics},
	init         = _ols_init,
	shutdown     = _ols_shutdown,
	on_diagnostics  = _ols_on_diagnostics,
	on_code_actions = _ols_on_code_actions,
	on_hover        = nil,
	on_rename       = nil,
	free_result     = _ols_free_result,
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


// ── Memory management ──────────────────────────────────────────────────────────

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
