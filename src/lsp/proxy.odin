/*
	olt-lsp — LSP Proxy Server
	File: src/lsp/proxy.odin

	Acts as the single LSP endpoint for editors. Forwards all traffic
	transparently to a vanilla OLS subprocess, and injects odin-lint
	diagnostics into every textDocument/publishDiagnostics notification.

	Editor setup (VS Code settings.json example):
	    "odin.languageServer.path": "/path/to/artifacts/olt-lsp"

	The OLS binary path is configured via olt.toml:
	    [tools]
	    ols_path = "/path/to/ols"

	Build:
	    ./scripts/build_lsp.sh  →  artifacts/olt-lsp

	Architecture:
	    Thread A (main):  editor stdin  ──forward──► OLS stdin
	    Thread B (bg):    OLS stdout ──(inject)──► editor stdout
	    Analysis:         runs in Thread B on each publishDiagnostics event
*/
package lsp_proxy

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

import core "../core"

// =============================================================================
// Shared proxy state
// =============================================================================

ProxyState :: struct {
	ols:           OLSProcess,
	ts_parser:     core.TreeSitterASTParser,

	// Document content cache: URI → full source text.
	// Written by Thread A on didOpen/didChange, read by Thread B on publishDiagnostics.
	doc_mutex:     sync.Mutex,
	doc_cache:     map[string]string,
}

// ThreadBData is passed to the background thread proc.
ThreadBData :: struct {
	state: ^ProxyState,
}

// =============================================================================
// Thread B — OLS stdout → inject → editor stdout
// =============================================================================

_thread_b_proc :: proc(td: ^ThreadBData) {
	state := td.state

	buf := make([]u8, 64 * 1024)
	defer delete(buf)
	reader := ols_make_reader(&state.ols, buf)
	defer bufio.reader_destroy(&reader)

	for {
		raw, ok := _read_framed(&reader)
		if !ok { break }

		if is_publish_diagnostics(raw) {
			_handle_publish_diagnostics(state, raw)
		} else {
			_write_to_editor(raw)
		}
		delete(raw)
	}
}

@(private = "file")
_handle_publish_diagnostics :: proc(state: ^ProxyState, ols_msg: []u8) {
	uri := extract_publish_uri(ols_msg)
	if uri == "" {
		_write_to_editor(ols_msg)
		return
	}

	file_path := uri_to_path(uri)

	// Get document content from cache (set by Thread A on didOpen/didChange).
	sync.mutex_lock(&state.doc_mutex)
	cached_content, has_content := state.doc_cache[uri]
	content := strings.clone(cached_content) if has_content else ""
	sync.mutex_unlock(&state.doc_mutex)
	defer delete(content)

	// Fall back to disk if content not in cache yet.
	if content == "" && os.is_file(file_path) {
		bytes, err := os.read_entire_file_from_path(file_path, context.temp_allocator)
		if err == nil { content = strings.clone(string(bytes)) }
	}

	// Run our analysis.
	our_diags := make([dynamic]core.Diagnostic)
	defer delete(our_diags)

	if content != "" {
		core.analyze_content(file_path, content, &state.ts_parser, &our_diags)
	}

	// Merge and send.  Both returned strings are heap-allocated; delete after use.
	our_items := diags_to_lsp_items(our_diags[:])
	defer if len(our_items) > 0 { delete(our_items) }
	merged    := merge_publish_diagnostics(ols_msg, our_items)
	defer delete(merged)
	_write_to_editor_str(merged)
}

// =============================================================================
// Thread A — editor stdin → OLS stdin (main thread after startup)
// =============================================================================

_run_thread_a :: proc(state: ^ProxyState) {
	stdin_buf := make([]u8, 64 * 1024)
	defer delete(stdin_buf)

	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, os.to_reader(os.stdin), stdin_buf)
	defer bufio.reader_destroy(&reader)

	for {
		raw, ok := _read_framed(&reader)
		if !ok { break }

		// Cache document content for Thread B to use.
		if is_doc_event(raw) {
			uri, content := extract_doc_info(raw)
			if uri != "" && content != "" {
				sync.mutex_lock(&state.doc_mutex)
				if old, exists := state.doc_cache[uri]; exists {
					// Key already owned by map — just replace the value.
					delete(old)
					state.doc_cache[uri] = strings.clone(content)
				} else {
					// New URI: clone both key and value so they outlive `raw`.
					state.doc_cache[strings.clone(uri)] = strings.clone(content)
				}
				sync.mutex_unlock(&state.doc_mutex)
			}
		}

		// Forward to OLS.
		ols_write(&state.ols, raw)
		delete(raw)
	}
}

// =============================================================================
// Main entry point
// =============================================================================

main :: proc() {
	// Locate OLS binary: read olt.toml if present, fall back to PATH.
	cfg := core.load_project_config([]string{"."})
	ols_path := core.effective_ols_path(cfg)

	// Initialise tree-sitter for our analysis.
	ts_parser, ts_ok := core.initTreeSitterParser()
	if !ts_ok {
		fmt.eprintln("olt-lsp: failed to initialise tree-sitter parser")
		os.exit(1)
	}

	// Start OLS subprocess.
	ols_proc, ols_ok := ols_start(ols_path)
	if !ols_ok {
		fmt.eprintfln("olt-lsp: could not start OLS at '%s'", ols_path)
		fmt.eprintln("  Set [tools] ols_path in olt.toml or ensure 'ols' is in PATH.")
		fmt.eprintln("  Vanilla OLS: https://github.com/DanielGavin/ols")
		os.exit(1)
	}

	state := new(ProxyState)
	state.ols       = ols_proc
	state.ts_parser = ts_parser
	state.doc_cache = make(map[string]string)

	// Launch Thread B (OLS stdout → editor).
	tb_data := new(ThreadBData)
	tb_data.state = state
	t := thread.create_and_start_with_poly_data(tb_data, _thread_b_proc)
	_ = t // thread runs until OLS stdout closes

	// Thread A is the main thread (editor stdin → OLS).
	_run_thread_a(state)

	// Editor closed the connection — shut down cleanly.
	ols_stop(&state.ols)

	// Free document cache and proxy state.
	// NOTE: tree-sitter is NOT thread-safe. state.ts_parser is only accessed
	// from Thread B (analyze_content). Thread A must never call analyze_content.
	// If Thread A ever needs analysis, protect ts_parser with a separate mutex.
	for uri, content in state.doc_cache { delete(uri); delete(content) }
	delete(state.doc_cache)
	free(state)
	free(tb_data)
}

// =============================================================================
// Internal helpers
// =============================================================================

// _read_framed reads one Content-Length framed message.
// Allocates on the heap; caller must delete the returned slice.
@(private = "file")
_read_framed :: proc(reader: ^bufio.Reader) -> (bytes: []u8, ok: bool) {
	content_length := -1
	for {
		line, err := bufio.reader_read_string(reader, '\n', context.temp_allocator)
		if err != nil { return nil, false }
		line = strings.trim_right(line, "\r\n")
		if line == "" { break }
		if strings.has_prefix(line, "Content-Length:") {
			val := strings.trim_space(line[len("Content-Length:"):])
			n := 0
			for ch in val {
				if ch >= '0' && ch <= '9' { n = n*10 + int(ch - '0') } else { break }
			}
			content_length = n
		}
	}
	if content_length < 0 { return nil, false }
	if content_length == 0 { return []u8{}, true }

	buf := make([]u8, content_length)
	total := 0
	for total < content_length {
		n, err := bufio.reader_read(reader, buf[total:])
		total += n
		if err != nil && total < content_length { delete(buf); return nil, false }
	}
	return buf, true
}

// _write_to_editor sends a framed message to the editor (our stdout).
// Thread B is the only caller — no mutex needed.
@(private = "file")
_write_to_editor :: proc(bytes: []u8) {
	header := fmt.tprintf("Content-Length: %d\r\n\r\n", len(bytes))
	w := os.to_writer(os.stdout)
	io.write_string(w, header) // olt:ignore C201
	io.write(w, bytes)         // olt:ignore C201
}

@(private = "file")
_write_to_editor_str :: proc(s: string) {
	_write_to_editor(transmute([]u8)s)
}
