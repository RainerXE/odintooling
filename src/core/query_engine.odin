package core

import "core:fmt"
import "core:strings"
import "core:mem"

// QueryResult holds one match from a compiled SCM query.
// captures maps capture name (e.g. "var_name") to the matched TSNode.
QueryResult :: struct {
    captures:      map[string]TSNode,
    pattern_index: int,
}

// CompiledQuery wraps a compiled tree-sitter query and its capture name table.
// Create once at startup with load_query(); pass to run_query() per file.
CompiledQuery :: struct {
    handle:        rawptr,          // ts_query handle
    capture_names: []string,        // index → capture name string
    language:      rawptr,
}

// load_query_src compiles an SCM source string into a CompiledQuery.
// src: SCM query source (typically from a #load compile-time constant)
// label: human-readable name used in error messages (e.g. "memory_safety.scm")
// Returns: (query, true) on success, ({}, false) on error.
load_query_src :: proc(language: rawptr, src: string, label: string = "<embedded>") -> (CompiledQuery, bool) {
    source_ptr := cstring(cast(^u8)raw_data(src)) if len(src) > 0 else nil

    error_offset: u32
    error_type:   TSQueryError
    handle := ts_query_new(language, source_ptr, u32(len(src)), &error_offset, &error_type) // odin-lint:ignore C011 handle transferred into returned CompiledQuery struct

    if handle == nil || error_type != .None {
        fmt.eprintfln("[query_engine] SCM compile error in %s at byte %d: %v",
            label, error_offset, error_type)
        return {}, false
    }

    count  := ts_query_capture_count(handle)
    names  := make([]string, count)
    for i in 0..<count {
        length: u32
        raw_ptr := ts_query_capture_name_for_id(handle, i, &length)
        if raw_ptr != nil && length > 0 {
            cstr := strings.string_from_null_terminated_ptr(cast(^u8)raw_ptr, 1024)
            names[i] = strings.clone(cstr)
        }
    }

    return CompiledQuery{
        handle        = handle,
        capture_names = names,
        language      = language,
    }, true
}


// unload_query frees all memory owned by the query.
// Call this at shutdown (once per query, not per file).
unload_query :: proc(q: ^CompiledQuery) {
    if q.handle != nil {
        ts_query_delete(q.handle)
        q.handle = nil
    }
    for name in q.capture_names {
        delete(name)
    }
    delete(q.capture_names)
}

// run_query runs a compiled query over an AST root node.
// Returns a slice of QueryResult — one entry per match found.
// Caller must delete the returned slice and each result's captures map.
run_query :: proc(
    q:          ^CompiledQuery,
    root:       TSNode,
    file_lines: []string,
) -> []QueryResult {
    results := make([dynamic]QueryResult)

    cursor := ts_query_cursor_new()
    defer ts_query_cursor_delete(cursor)

    ts_query_cursor_exec(cursor, q.handle, root)

    match: TSQueryMatch
    for ts_query_cursor_next_match(cursor, &match) {
        result := QueryResult{
            captures      = make(map[string]TSNode),
            pattern_index = int(match.pattern_index),
        }
        // Access captures - match.captures is a pointer to array of TSQueryCapture
        // We need to cast to a slice to access elements safely
        captures_slice := mem.slice_ptr(match.captures, int(match.capture_count))
        for i in 0..<int(match.capture_count) {
            cap := captures_slice[i]
            if int(cap.index) < len(q.capture_names) {
                name := q.capture_names[int(cap.index)]
                result.captures[name] = cap.node
            }
        }
        append(&results, result)
    }

    return results[:]
}

// free_query_results frees the slice returned by run_query.
free_query_results :: proc(results: []QueryResult) {
    for &r in results {
        delete(r.captures)
    }
    delete(results)
}