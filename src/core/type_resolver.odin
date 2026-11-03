// type_resolver.odin — return-type heuristics for proc calls used by C201 and C019 Phase 2.
// TypeResolveContext holds what C201 knows about the file it is checking; the curated list covers
// common stdlib procs that return (T, bool) or (T, Error) patterns, and the package index reads
// everything else from the source of the package the call goes to.
package core

import "core:os"
import "core:path/filepath"
import "core:strings"

// =============================================================================
// Lightweight type resolver for C201 (unchecked error return detection)
//
// Resolution order for a call such as `os.close(f)` or `util.run()`:
//   1. stdlib curated list — instant, zero overhead
//   2. graph DB lookup    — checks the stored return_type of a project procedure called by its bare name
//   3. package source     — the qualifier names an import; read that package's declarations and look at the
//                           return type of the procedure. Imports under core:, base: and vendor: are read from
//                           the Odin installation (ODIN_ROOT, or `odin root`); relative imports from the project.
//                           Without an Odin installation only the project's own packages resolve.
// =============================================================================

TypeResolveContext :: struct {
    db:       ^GraphDB,
    file_dir: string,              // directory of the file being checked: relative imports are relative to it
    imports:  map[string]string,   // the file's imports: the name a qualifier uses -> the import path
}

// proc_returns_error returns true if the named procedure is known to return
// an error type. Conservative: returns false if uncertain (avoids false positives).
proc_returns_error :: proc(ctx: ^TypeResolveContext, proc_name: string) -> bool {
    if _stdlib_returns_error(proc_name) { return true }
    if ctx != nil && ctx.db != nil {
        if _graph_returns_error(ctx.db, proc_name) { return true }
    }
    if ctx != nil {
        if dot := strings.index_byte(proc_name, '.'); dot > 0 {
            if _package_returns_error(ctx, proc_name[:dot], proc_name[dot+1:]) { return true }
        }
    }
    return false
}

// _stdlib_returns_error checks against a curated list of stdlib error-returning procs.
// Only package-qualified names are used (e.g. "net.send", not bare "send") to avoid
// false-positives when user code defines procs with the same short name.
@(private)
_stdlib_returns_error :: proc(name: string) -> bool {
    switch name {
    // core:os
    case "os.open":   return true
    case "os.read":   return true
    case "os.write":  return true
    case "os.close":  return true
    case "os.stat":   return true
    case "os.lstat":  return true
    case "os.mkdir":  return true
    case "os.remove": return true
    case "os.rename": return true
    case "os.read_entire_file_from_path": return true
    case "os.write_entire_file":          return true
    case "os.read_entire_file":           return true
    case "os.make_directory":             return true
    case "os.remove_directory":           return true
    case "os.copy_file":                  return true
    // core:net
    case "net.dial_tcp":       return true
    case "net.listen_tcp":     return true
    case "net.accept":         return true
    case "net.send":           return true
    case "net.recv":           return true
    case "net.resolve_ip":     return true
    case "net.parse_endpoint": return true
    // core:encoding/json
    case "json.marshal":   return true
    case "json.unmarshal": return true
    case "json.parse":     return true
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


// =============================================================================
// Step 3: read the package a qualified call goes to
// =============================================================================

// PackageIndex says, for each procedure a package declares, whether it returns an error.
@(private="file")
PackageIndex :: struct {
    returns_error: map[string]bool,
    external:      bool,   // from the Odin installation: cannot change while we run
    stamp:         u64,    // the package's .odin files (names, sizes, modification times) when it was read
    checked:       int,    // the lint run that last confirmed the stamp
}

// Packages are read once and kept, whichever file asks. A project package can be edited while a long-running process
// (the LSP proxy, the MCP server) is alive, so each lint run re-checks its files once; the Odin installation is not rechecked.
@(private="file") _resolve_run:     int
@(private="file") _package_cache:   map[string]^PackageIndex
@(private="file") _odin_root:       string
@(private="file") _odin_root_known: bool

// resolver_begin_run marks the start of one lint run: a cached project package is re-checked against its files once per run.
resolver_begin_run :: proc() { _resolve_run += 1 }

// _package_returns_error resolves `qualifier.name` through the checked file's imports.
@(private="file")
_package_returns_error :: proc(ctx: ^TypeResolveContext, qualifier, name: string) -> bool {
    path, has := ctx.imports[qualifier]
    if !has { return false }
    dir, external := _import_dir(path, ctx.file_dir)
    if dir == "" { return false }
    idx := _package_index(dir, external)
    if idx == nil { return false }
    return idx.returns_error[name]
}

// _import_dir maps an import path to the directory holding that package's source, or "" when it cannot be
// found: an unknown collection (`shared:`), or core:/base:/vendor: without an Odin installation.
@(private="file")
_import_dir :: proc(path, file_dir: string) -> (dir: string, external: bool) {
    if colon := strings.index_byte(path, ':'); colon > 0 {
        switch path[:colon] {
        case "core", "base", "vendor":
            root := _find_odin_root()
            if root == "" { return "", false }
            joined, _ := filepath.join({root, path[:colon], path[colon+1:]}, context.temp_allocator)
            return joined, true
        }
        return "", false
    }
    if file_dir == "" { return "", false }
    joined, _ := filepath.join({file_dir, path}, context.temp_allocator)
    return joined, false
}

// _find_odin_root finds the Odin installation: ODIN_ROOT, else whatever `odin root` prints.
@(private="file")
_find_odin_root :: proc() -> string {
    if _odin_root_known { return _odin_root }
    _odin_root_known = true
    if env := os.get_env("ODIN_ROOT", context.allocator); env != "" {
        core_dir, _ := filepath.join({env, "core"}, context.temp_allocator)
        if os.is_dir(core_dir) {
            _odin_root = env
            return _odin_root
        }
        delete(env)
    }
    cmd := []string{"odin", "root"}
    state, stdout, stderr, err := os.process_exec(os.Process_Desc{command = cmd}, context.allocator)
    defer delete(stdout)
    defer delete(stderr)
    if err != nil || !state.success { return "" }
    root := strings.trim_space(string(stdout))
    core_dir, _ := filepath.join({root, "core"}, context.temp_allocator)
    if root != "" && os.is_dir(core_dir) { _odin_root = strings.clone(root) }
    return _odin_root
}

// _package_index parses the .odin files directly inside dir (once) and records which procedures return an error.
@(private="file")
_package_index :: proc(dir: string, external: bool) -> ^PackageIndex {
    if _package_cache == nil { _package_cache = make(map[string]^PackageIndex) }
    cached, was_cached := _package_cache[dir]
    // An installation package never changes; a project package is re-checked once per lint run, and one that could not
    // be read is tried again, since it may have been created since.
    if was_cached && (external || (cached != nil && cached.checked == _resolve_run)) { return cached }

    handle, open_err := os.open(dir)
    if open_err != nil { return _remember(dir, nil) }
    defer os.close(handle)
    infos, read_err := os.read_dir(handle, -1, context.allocator)
    if read_err != nil { return _remember(dir, nil) }
    defer {
        for info in infos { os.file_info_delete(info, context.allocator) }
        delete(infos)
    }

    stamp := _dir_stamp(infos)
    if was_cached && cached != nil && cached.stamp == stamp {
        cached.checked = _resolve_run   // unchanged since it was read
        return cached
    }

    adapter, adapter_ok := initASTAdapter()
    if !adapter_ok { return nil }
    defer deinitASTAdapter(adapter)

    idx := new(PackageIndex)
    idx.returns_error = make(map[string]bool)
    idx.external = external
    idx.stamp    = stamp
    idx.checked  = _resolve_run
    groups := make(map[string][dynamic]string, context.temp_allocator)

    for info in infos {
        if os.is_dir(info.fullpath) || !strings.has_suffix(info.name, ".odin") || strings.has_suffix(info.name, "_test.odin") { continue }
        data, rerr := os.read_entire_file_from_path(info.fullpath, context.allocator)
        if rerr != nil { continue }
        defer delete(data)
        source := string(data)
        tree, tree_ok := parseSource(adapter.parser, adapter.language, source)
        if !tree_ok { continue }
        defer ts_tree_delete(tree)
        root := getRootNode(tree)
        if ts_node_is_null(root) { continue }
        _index_declarations(root, source, idx, &groups)
    }

    // A procedure group returns an error only when every procedure it lists does: a call could be any of them.
    for name, members in groups {
        all := len(members) > 0
        for m in members { if !idx.returns_error[m] { all = false; break } }
        if all { idx.returns_error[strings.clone(name)] = true }
    }

    return _remember(dir, idx)
}

// _remember stores a package (or nil for one that cannot be read) under its directory and returns it.
@(private="file")
_remember :: proc(dir: string, idx: ^PackageIndex) -> ^PackageIndex {
    if _, ok := _package_cache[dir]; !ok { _package_cache[strings.clone(dir)] = idx } else { _package_cache[dir] = idx }
    return idx
}

// _dir_stamp summarises a package's .odin files, so an edit to any of them is noticed.
@(private="file")
_dir_stamp :: proc(infos: []os.File_Info) -> u64 {
    stamp := u64(1469598103934665603)
    for info in infos {
        if !strings.has_suffix(info.name, ".odin") { continue }
        stamp ~= u64(hash_string_fnv(info.name))
        stamp *= 1099511628211
        stamp ~= u64(info.size)
        stamp *= 1099511628211
        stamp ~= u64(info.modification_time._nsec)
        stamp *= 1099511628211
    }
    return stamp
}

@(private="file")
hash_string_fnv :: proc(s: string) -> u64 {
    h := u64(14695981039346656037)
    for i in 0 ..< len(s) { h ~= u64(s[i]); h *= 1099511628211 }
    return h
}

// _index_declarations records the procedures declared at the top of a file, including inside `when` blocks.
@(private="file")
_index_declarations :: proc(node: TSNode, source: string, idx: ^PackageIndex, groups: ^map[string][dynamic]string) {
    for i in 0 ..< int(ts_node_child_count(node)) {
        c := ts_node_child(node, u32(i))
        switch string(ts_node_type(c)) {
        case "procedure_declaration":
            name, ret := _proc_name_and_result(c, source)
            if name != "" && !_is_stream_output(name) && _result_is_error(ret) { idx.returns_error[strings.clone(name)] = true }
        case "overloaded_procedure_declaration":
            // the first identifier is the group's name, the rest are the procedures it lists
            gname := ""
            for j in 0 ..< int(ts_node_child_count(c)) {
                id := ts_node_child(c, u32(j))
                if string(ts_node_type(id)) != "identifier" { continue }
                text := source[ts_node_start_byte(id):ts_node_end_byte(id)]
                // the file's text is freed once this file is done, and the groups are resolved after all files: copy
                if gname == "" {
                    gname = strings.clone(text, context.temp_allocator)
                } else {
                    list := groups[gname]
                    append(&list, strings.clone(text, context.temp_allocator))
                    groups[gname] = list
                }
            }
        case "when_statement", "block":
            _index_declarations(c, source, idx, groups)
        }
    }
}

// _proc_name_and_result reads a procedure_declaration: its name and the text of its result type ("" if none).
@(private="file")
_proc_name_and_result :: proc(decl: TSNode, source: string) -> (name, result: string) {
    for i in 0 ..< int(ts_node_child_count(decl)) {
        c := ts_node_child(decl, u32(i))
        switch string(ts_node_type(c)) {
        case "identifier":
            if name == "" { name = source[ts_node_start_byte(c):ts_node_end_byte(c)] }
        case "procedure":
            // the result is the `type` that follows the parameters; the parameters' own types sit inside `parameters`
            for j in 0 ..< int(ts_node_child_count(c)) {
                k := ts_node_child(c, u32(j))
                if string(ts_node_type(k)) == "type" { result = source[ts_node_start_byte(k):ts_node_end_byte(k)]; break }
            }
        }
    }
    return
}

// _is_stream_output names the procedures that write to a stream: write_string, write_byte, buffer_write_rune, flush, print.
// They return an io.Error (or an os.Error) that Odin code discards as a matter of course, because the destination is usually a
// strings.Builder or stdout and cannot meaningfully fail. Odin's own repository discards the result of io.write_string 230
// times. Reporting them would drown the rest, so reading the package source leaves them out. The curated list is unaffected:
// os.write, os.write_entire_file and friends stay reported.
@(private="file")
_is_stream_output :: proc(name: string) -> bool {
    return strings.has_prefix(name, "write") || strings.has_prefix(name, "flush") || strings.has_prefix(name, "print") ||
           strings.contains(name, "_write")
}

// _result_is_error: does a result type mention an error? An allocator error (`mem.Allocator_Error`) does not count.
// Odin treats it as optional (`#optional_allocator_error`) and code ignores the result of free and friends all the time,
// so reporting it would bury the errors that matter, such as a failed write.
@(private="file")
_result_is_error :: proc(result: string) -> bool {
    start := -1
    for i := 0; i <= len(result); i += 1 {
        in_word := i < len(result) && (result[i] == '_' || (result[i] >= 'a' && result[i] <= 'z') || (result[i] >= 'A' && result[i] <= 'Z') || (result[i] >= '0' && result[i] <= '9'))
        if in_word {
            if start < 0 { start = i }
        } else if start >= 0 {
            word := result[start:i]
            start = -1
            if strings.contains(word, "Error") && word != "Allocator_Error" { return true }
        }
    }
    return false
}
