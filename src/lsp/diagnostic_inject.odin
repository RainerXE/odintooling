package lsp_proxy

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import core "../core"

// =============================================================================
// Diagnostic injection — merge odin-lint diagnostics into LSP notifications
// =============================================================================
//
// LSP uses 0-indexed line/character; our Diagnostic uses 1-indexed line/column.
// publishDiagnostics severity: Error=1 Warning=2 Info=3 Hint=4
// =============================================================================

// lsp_severity maps our rule tier to LSP severity.
@(private = "file")
lsp_severity :: proc(tier: string) -> int {
	switch tier {
	case "correctness", "structural": return 1 // Error
	case "style", "migration":        return 2 // Warning
	}
	return 3 // Info
}

// diags_to_lsp_items builds a JSON fragment — a comma-separated sequence of
// LSP Diagnostic objects (no surrounding brackets).
// Returns "" if no diags. When non-empty, returns a heap-allocated string the
// caller must delete.
diags_to_lsp_items :: proc(diags: []core.Diagnostic) -> string {
	if len(diags) == 0 { return "" }
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	first := true
	for d in diags {
		if d.diag_type == .NONE || d.diag_type == .INTERNAL_ERROR { continue }
		if !first { strings.write_string(&sb, ",") }
		first = false
		line    := max(d.line - 1, 0)
		col     := max(d.column - 1, 0)
		end_col := col + 20
		sev     := lsp_severity(d.tier)
		strings.write_string(&sb, `{"range":{"start":{"line":`)
		fmt.sbprint(&sb, line)
		strings.write_string(&sb, `,"character":`)
		fmt.sbprint(&sb, col)
		strings.write_string(&sb, `},"end":{"line":`)
		fmt.sbprint(&sb, line)
		strings.write_string(&sb, `,"character":`)
		fmt.sbprint(&sb, end_col)
		strings.write_string(&sb, `}},"severity":`)
		fmt.sbprint(&sb, sev)
		strings.write_string(&sb, `,"code":"`)
		strings.write_string(&sb, d.rule_id)
		strings.write_string(&sb, `","source":"olt","message":"`)
		_lsp_write_escaped(&sb, d.message)
		strings.write_byte(&sb, '"')
		if d.fix != "" {
			strings.write_string(&sb, `,"relatedInformation":[{"location":{"uri":"","range":{"start":{"line":`)
			fmt.sbprint(&sb, line)
			strings.write_string(&sb, `,"character":`)
			fmt.sbprint(&sb, col)
			strings.write_string(&sb, `},"end":{"line":`)
			fmt.sbprint(&sb, line)
			strings.write_string(&sb, `,"character":`)
			fmt.sbprint(&sb, end_col)
			strings.write_string(&sb, `}}},"message":"Fix: `)
			_lsp_write_escaped(&sb, d.fix)
			strings.write_string(&sb, `"}]`)
		}
		strings.write_string(&sb, "}")
	}
	return strings.clone(strings.to_string(sb))
}

// _lsp_write_escaped writes s to sb with full JSON string escaping
// per RFC 8259: \, ", and all control characters < 0x20.
@(private = "file")
_lsp_write_escaped :: proc(sb: ^strings.Builder, s: string) {
	for b in transmute([]u8)s {
		switch b {
		case '"':  strings.write_string(sb, `\"`)
		case '\\': strings.write_string(sb, `\\`)
		case '\n': strings.write_string(sb, `\n`)
		case '\r': strings.write_string(sb, `\r`)
		case '\t': strings.write_string(sb, `\t`)
		case 0..<0x20:
			// Other control characters → \uXXXX
			fmt.sbprintf(sb, `\u%04x`, b)
		case:
			strings.write_byte(sb, b)
		}
	}
}

// merge_publish_diagnostics takes an OLS publishDiagnostics notification byte
// slice and returns a new heap-allocated notification string with our
// diagnostics appended. The caller must delete the returned string.
// If our_items is empty, returns a clone of the original message.
merge_publish_diagnostics :: proc(ols_bytes: []u8, our_items: string) -> string {
	if our_items == "" { return strings.clone(string(ols_bytes)) }

	s := string(ols_bytes)

	key := `"diagnostics":[`
	pos := strings.index(s, key)
	if pos < 0 { return strings.clone(s) }

	arr_start := pos + len(key) // first char inside [

	// Find the matching ] tracking depth and skipping chars inside JSON strings.
	// This prevents ] inside diagnostic message strings from closing the array.
	depth, in_string, escaped := 1, false, false
	arr_end := arr_start
	for arr_end < len(s) && depth > 0 {
		c := s[arr_end]
		if escaped {
			escaped = false
		} else if c == '\\' {
			escaped = true
		} else if c == '"' {
			in_string = !in_string
		} else if !in_string {
			if      c == '[' { depth += 1 }
			else if c == ']' { depth -= 1 }
		}
		if depth > 0 { arr_end += 1 }
	}

	inner     := strings.trim_space(s[arr_start:arr_end])
	separator := "," if len(inner) > 0 else ""

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	strings.write_string(&sb, s[:arr_start])
	strings.write_string(&sb, inner)
	strings.write_string(&sb, separator)
	strings.write_string(&sb, our_items)
	strings.write_string(&sb, s[arr_end:])
	return strings.clone(strings.to_string(sb))
}

// extract_publish_uri extracts the document URI from a publishDiagnostics
// notification. Returns "" if not found.
extract_publish_uri :: proc(msg: []u8) -> string {
	val, err := json.parse(msg, allocator = context.temp_allocator)
	if err != nil { return "" }
	obj, ok := val.(json.Object)
	if !ok { return "" }
	params_val, has_p := obj["params"]
	if !has_p { return "" }
	params, ok2 := params_val.(json.Object)
	if !ok2 { return "" }
	uri_val, has_u := params["uri"]
	if !has_u { return "" }
	uri_str, ok3 := uri_val.(json.String)
	if !ok3 { return "" }
	return string(uri_str)
}

// extract_doc_info extracts (uri, text_content) from didOpen or didChange
// notifications. Returns ("", "") if not applicable.
extract_doc_info :: proc(msg: []u8) -> (uri: string, content: string) {
	val, err := json.parse(msg, allocator = context.temp_allocator)
	if err != nil { return }
	obj, ok := val.(json.Object)
	if !ok { return }

	method_val, _ := obj["method"]
	method, _      := method_val.(json.String)
	params_val, _  := obj["params"]
	params, ok2    := params_val.(json.Object)
	if !ok2 { return }

	switch string(method) {
	case "textDocument/didOpen":
		// params.textDocument.text
		td_val, _ := params["textDocument"]
		td, ok3   := td_val.(json.Object)
		if !ok3 { return }
		uri_val, _     := td["uri"]
		uri_s, ok4     := uri_val.(json.String)
		text_val, _    := td["text"]
		text_s, ok5    := text_val.(json.String)
		if ok4 && ok5 {
			uri     = string(uri_s)
			content = string(text_s)
		}

	case "textDocument/didChange":
		// params.textDocument.uri + params.contentChanges[0].text (full sync)
		td_val, _  := params["textDocument"]
		td, ok3    := td_val.(json.Object)
		if !ok3 { return }
		uri_val, _ := td["uri"]
		uri_s, ok4 := uri_val.(json.String)
		if !ok4 { return }
		uri = string(uri_s)

		changes_val, _ := params["contentChanges"]
		changes, ok5   := changes_val.(json.Array)
		if !ok5 || len(changes) == 0 { return }
		first_val, ok6 := changes[0].(json.Object)
		if !ok6 { return }
		text_val, _    := first_val["text"]
		text_s, ok7    := text_val.(json.String)
		if ok7 { content = string(text_s) }
	}
	return
}

// uri_to_path converts a file:// URI to a local filesystem path.
uri_to_path :: proc(uri: string) -> string {
	if strings.has_prefix(uri, "file://") {
		return uri[len("file://"):]
	}
	return uri
}

// is_doc_event returns true if the LSP method is one that carries document content.
is_doc_event :: proc(msg: []u8) -> bool {
	s := string(msg)
	return strings.contains(s, `"textDocument/didOpen"`)   ||
	       strings.contains(s, `"textDocument/didChange"`) ||
	       strings.contains(s, `"textDocument/didSave"`)
}

// is_publish_diagnostics returns true if the message is a publishDiagnostics
// notification from OLS.
is_publish_diagnostics :: proc(msg: []u8) -> bool {
	return strings.contains(string(msg), `"textDocument/publishDiagnostics"`)
}
