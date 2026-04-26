// type_resolver.odin — return-type heuristics for proc calls used by C201 and C019 Phase 2.
// TypeResolveContext wraps the graph DB for project-local proc lookups; the fallback
// list covers common stdlib procs that return (T, bool) or (T, Error) patterns.
package core

import "core:strings"

// =============================================================================
// Lightweight type resolver for C201 (unchecked error return detection)
//
// Resolution order:
//   1. stdlib curated list — instant, zero overhead
//   2. graph DB lookup    — checks stored return_type field
//   3. OLS stub           — reserved; always returns false for now
// =============================================================================

TypeResolveContext :: struct {
    db:       ^GraphDB,
    odin_path: string,
    ols_path:  string,
}

// proc_returns_error returns true if the named procedure is known to return
// an error type. Conservative: returns false if uncertain (avoids false positives).
proc_returns_error :: proc(ctx: ^TypeResolveContext, proc_name: string) -> bool {
    if _stdlib_returns_error(proc_name) { return true }
    if ctx != nil && ctx.db != nil {
        if _graph_returns_error(ctx.db, proc_name) { return true }
    }
    return false
}

// _stdlib_returns_error checks against a curated list of stdlib error-returning procs.
@(private)
_stdlib_returns_error :: proc(name: string) -> bool {
    switch name {
    // core:os
    case "os.open",  "open":  return true
    case "os.read",  "read":  return true
    case "os.write", "write": return true
    case "os.close", "close": return true
    case "os.stat",  "stat":  return true
    case "os.lstat", "lstat": return true
    case "os.mkdir", "mkdir": return true
    case "os.remove", "remove": return true
    case "os.rename", "rename": return true
    case "os.read_entire_file_from_path": return true
    case "os.write_entire_file":          return true
    case "os.read_entire_file":           return true
    case "os.make_directory":             return true
    case "os.remove_directory":           return true
    case "os.copy_file":                  return true
    case "os.exists":                     return false  // returns bool only
    case "os.is_file":                    return false
    case "os.is_dir":                     return false
    // core:net
    case "net.dial_tcp",  "dial_tcp":  return true
    case "net.listen_tcp","listen_tcp": return true
    case "net.accept",    "accept":    return true
    case "net.send",      "send":      return true
    case "net.recv",      "recv":      return true
    case "net.resolve_ip":             return true
    case "net.parse_endpoint":         return true
    // core:encoding/json
    case "json.marshal",   "marshal":   return true
    case "json.unmarshal", "unmarshal": return true
    case "json.parse",     "parse":     return true
    // core:strconv
    case "strconv.parse_int":   return false  // returns (int, bool)
    case "strconv.parse_float": return false
    case "strconv.parse_bool":  return false
    }
    return false
}

// _graph_returns_error queries the graph DB for the proc's stored return_type
// and checks whether it contains an error-indicating word.
@(private)
_graph_returns_error :: proc(db: ^GraphDB, proc_name: string) -> bool {
    if db == nil { return false }
    sym, ok := graph_get_node(db, proc_name)
    if !ok { return false }
    rt := sym.return_type
    if rt == "" { return false }
    // Conservative: only flag if the word "Error" appears (not just "bool").
    return strings.contains(rt, "Error") || strings.contains(rt, "error")
}
