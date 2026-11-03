// dna_exporter.odin — four-pass graph export: declarations, references, roles, violations.
// export_symbols walks all .odin files and writes nodes/edges/lint data into the
// SQLite graph DB, enabling cross-file analysis for C201, C202, C012-T3, and MCP queries.
package core

import "core:fmt"
import "core:hash"
import "core:os"
import "core:strings"
import "core:time"
import "base:runtime"
import sq "../../vendor/odin-sqlite3"

// Default output location relative to the project root.
GRAPH_DB_PATH     :: ".codegraph/olt.db"
SYMBOLS_JSON_PATH :: ".codegraph/symbols.json"

// ExportResult summarises what the exporter produced.
ExportResult :: struct {
    files_indexed:    int,
    nodes_written:    int,
    edges_written:    int,
    unresolved:       int,
    dead_code_count:  int,
    db_path:          string,
    symbols_path:     string,
    ok:               bool,
    cached:           bool,  // true when all files were unchanged and no rebuild was needed
}

// export_symbols runs the full 5-pass DNA export pipeline.
// paths: the same target list accepted by the CLI (files or directories).
// db_path: where to write the SQLite graph (defaults to GRAPH_DB_PATH).
// cfg: project config — used to gate optional dead-code rules (C014/C015).
export_symbols :: proc(
    paths:     []string,
    ts_parser: ^TreeSitterASTParser,
    db_path:   string = GRAPH_DB_PATH,
    cfg:       OdinLintConfig = {},
    respect_gitignore: bool = true,
) -> ExportResult {
    symbols_path := _symbols_path_for(db_path)
    result := ExportResult{db_path = db_path, symbols_path = symbols_path}

    if !graph_ensure_dir(db_path) {
        fmt.eprintfln("export-symbols: cannot create directory for %s", db_path)
        return result
    }

    db, db_ok := graph_open(db_path)
    if !db_ok {
        fmt.eprintfln("export-symbols: failed to open graph db at %s", db_path)
        return result
    }
    defer graph_close(db)

    // A graph filled by an older analysis is rebuilt, not trusted: unchanged files would keep its results.
    if graph_analysis_stale(db) {
        graph_clear(db)
    }

    files := collect_odin_files(paths, true, false, nil, respect_gitignore)
    defer {
        for f in files { delete(f) }
        delete(files)
    }

    // -----------------------------------------------------------------------
    // Incremental rebuild — compute content hashes, skip unchanged files,
    // evict deleted files.
    // -----------------------------------------------------------------------
    known_hashes := graph_known_file_hashes(db)
    defer graph_free_file_hashes(&known_hashes)

    // Build set of current file paths for eviction detection.
    current_set := make(map[string]bool, context.temp_allocator)
    for f in files { current_set[f] = true }

    // Evict files that no longer exist.
    for known_path in known_hashes {
        if known_path not_in current_set {
            graph_evict_file(db, known_path)
        }
    }

    // Compute per-file hashes; build list of files that need re-indexing.
    now_ts := i64(time.now()._nsec / 1_000_000_000)
    changed_files := make([dynamic]string, context.temp_allocator)
    file_hashes   := make(map[string]string, context.temp_allocator)

    for file_path in files {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil { continue }
        h := hash.fnv64a(content)
        hash_str := fmt.tprintf("%x", h)
        delete(content)

        file_hashes[file_path] = hash_str
        known_h, is_known := known_hashes[file_path]
        if is_known && known_h == hash_str {
            continue  // unchanged — skip
        }
        // Changed or new — evict old data then re-index.
        if is_known { graph_evict_file(db, file_path) }
        append(&changed_files, file_path)
    }

    if len(changed_files) == 0 {
        // Nothing changed — return cached result.
        result.nodes_written = _count_table(db, "nodes")
        result.edges_written = _count_table(db, "edges")
        result.unresolved    = _count_table(db, "unresolved_refs")
        result.ok     = true
        result.cached = true
        return result
    }

    // -----------------------------------------------------------------------
    // Pass 1 — Index all symbol declarations into nodes.
    // -----------------------------------------------------------------------
    decl_q, decl_q_ok := load_query_src(ts_parser.adapter.language, DECLARATIONS_SCM, "declarations.scm")
    if !decl_q_ok {
        fmt.eprintln("export-symbols: failed to compile declarations.scm query")
        return result
    }
    defer unload_query(&decl_q)

    for file_path in changed_files {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil { continue }

        lines := strings.split(string(content), "\n")

        if h, ok2 := file_hashes[file_path]; ok2 {
            graph_insert_file(db, file_path, h, now_ts, len(content), len(lines))
        }

        tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
        if tree_ok {
            root := getRootNode(tree)
            if !ts_node_is_null(root) {
                _pass1_index_declarations(db, file_path, root, lines, &decl_q)
                result.files_indexed += 1
            }
            ts_tree_delete(tree)
        }
        delete(lines)
        delete(content)
    }

    // -----------------------------------------------------------------------
    // Pass 2 — Resolve call sites into edges.
    // -----------------------------------------------------------------------
    ref_q, ref_q_ok := load_query_src(ts_parser.adapter.language, REFERENCES_SCM, "references.scm")
    if !ref_q_ok {
        fmt.eprintln("export-symbols: failed to compile references.scm query")
        return result
    }
    defer unload_query(&ref_q)

    // Pass 2 re-walks every file, so it re-emits every unresolved reference:
    // drop the old ones first or each incremental run would duplicate them.
    sq.db_exec(db.conn, "DELETE FROM unresolved_refs;")

    // Procedure groups link to their members, which may live in any file.
    graph_resolve_group_members(db)
    for file_path in files {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil { continue }

        lines := strings.split(string(content), "\n")

        tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
        if tree_ok {
            root := getRootNode(tree)
            if !ts_node_is_null(root) {
                _pass2_resolve_calls(db, file_path, root, lines, &ref_q)
            }
            ts_tree_delete(tree)
        }
        delete(lines)
        delete(content)
    }

    // -----------------------------------------------------------------------
    // Pass 2b — Ownership across procedure boundaries: now that calls are resolved, read
    // allocation through the procedures that return it and through those that free it.
    // -----------------------------------------------------------------------
    _pass2b_cross_ownership(db, ts_parser)
    // Procedures link to the types they allocate (needs every file's types and imports).
    graph_resolve_alloc_types(db)

    // -----------------------------------------------------------------------
    // Pass 3 — Tag memory roles via heuristic analysis.
    // -----------------------------------------------------------------------
    _pass3_tag_memory_roles(db)

    // -----------------------------------------------------------------------
    // Pass 4 — Attach lint violations to nodes.
    // -----------------------------------------------------------------------
    dummy_opts := LintOptions{recursive = true}
    dummy_opts.config = default_config()
    _pass4_attach_violations(db, files[:], ts_parser, dummy_opts)

    // -----------------------------------------------------------------------
    // Pass 5 — Dead code detection (C014: private procs with zero callers).
    // Only runs when dead_code domain is enabled in config.
    // -----------------------------------------------------------------------
    if config_domain_enabled("C014", cfg) {
        dead_diags := c014_query_dead_procs(db)
        defer delete(dead_diags)
        for d in dead_diags {
            fmt.printfln("%s:%d:%d: %s [%s] %s",
                d.file, d.line, d.column, d.rule_id, d.tier, d.message)
        }
        result.dead_code_count += len(dead_diags)
    }

    if config_domain_enabled("C015", cfg) {
        dead_diags := c015_query_dead_consts(db, files[:])
        defer delete(dead_diags)
        for d in dead_diags {
            fmt.printfln("%s:%d:%d: %s [%s] %s",
                d.file, d.line, d.column, d.rule_id, d.tier, d.message)
        }
        result.dead_code_count += len(dead_diags)
    }

    // -----------------------------------------------------------------------
    // Pass 6 — Per-file counts and project metadata. (CodeGraph's triggers
    // keep the FTS5 index current on every insert.)
    // -----------------------------------------------------------------------
    graph_finalize(db, OLT_VERSION)

    // -----------------------------------------------------------------------
    // Pass 7 — Write symbols.json.
    // -----------------------------------------------------------------------
    _pass5_write_symbols_json(db, symbols_path)
    result.nodes_written = _count_table(db, "nodes")
    result.edges_written = _count_table(db, "edges")
    result.unresolved    = _count_table(db, "unresolved_refs")
    result.ok = true
    return result
}

// _symbols_path_for derives the symbols.json path from the db path.
// "/tmp/my.db" → "/tmp/symbols.json"; ".codegraph/graph.db" → ".codegraph/symbols.json"
@(private)
_symbols_path_for :: proc(db_path: string) -> string {
    dir := filepath_dir(db_path)
    if dir == "" || dir == "." {
        return "symbols.json"
    }
    return strings.join([]string{dir, "symbols.json"}, "/")
}

// =============================================================================
// Pass 1 — Declarations
// =============================================================================

// _index_proc_group indexes `name :: proc { a, b }`: one function node for the group, and
// a record of each member name (linked to its procedure by graph_resolve_group_members).
// The declaration's identifier children are the name first, then the members.
@(private)
_index_proc_group :: proc(db: ^GraphDB, file_path: string, group: TSNode, pkg: string, lines: []string) {
    name_node: TSNode
    members := make([dynamic]TSNode, context.temp_allocator)
    for i: u32 = 0; i < ts_node_child_count(group); i += 1 {
        c := ts_node_child(group, i)
        if string(ts_node_type(c)) != "identifier" { continue }
        if ts_node_is_null(name_node) { name_node = c } else { append(&members, c) }
    }
    if ts_node_is_null(name_node) { return }
    name := naming_extract_text(name_node, lines)
    if name == "" { return }

    pt   := ts_node_start_point(name_node)
    line := int(pt.row) + 1
    sig  := strings.builder_make(context.temp_allocator)
    strings.write_string(&sig, "proc { ")
    for m, i in members {
        if i > 0 { strings.write_string(&sig, ", ") }
        strings.write_string(&sig, naming_extract_text(m, lines))
    }
    strings.write_string(&sig, " }")

    node_id := graph_insert_node(db, name, fmt.tprintf("%s::%s", pkg, name), "function", file_path, line,
        strings.to_string(sig), !proc_node_is_private(name_node, lines),
        end_line  = _decl_end_line(group, line),
        start_col = int(pt.column),
        end_col   = int(ts_node_end_point(name_node).column))
    if node_id < 0 { return }

    for m in members {
        member_name := naming_extract_text(m, lines)
        if member_name == "" { continue }
        mp := ts_node_start_point(m)
        graph_add_group_member(db, node_id, member_name, int(mp.row) + 1, int(mp.column))
    }
}

@(private)
_decl_end_line :: proc(decl: TSNode, fallback: int) -> int {
    if ts_node_is_null(decl) { return fallback }
    return int(ts_node_end_point(decl).row) + 1
}

@(private)
_pass1_index_declarations :: proc(
    db:        ^GraphDB,
    file_path: string,
    root:      TSNode,
    lines:     []string,
    q:         ^CompiledQuery,
) {
    matches := run_query(q, root, lines)
    defer free_query_results(matches)

    // An Odin package is a directory; qualified names are "<package>::<name>".
    pkg := _package_from_path(file_path)   // until the file's `package` line says otherwise

    for &m in matches {
        if pkg_node, has_pkg := m.captures["package_name"]; has_pkg {
            pkg_name := naming_extract_text(pkg_node, lines)
            if pkg_name != "" {
                graph_set_package(db, file_path, pkg_name)
                pkg = pkg_name   // qualified names use the declared name, not the directory's
            }
            continue
        }
        if group, has_group := m.captures["group_decl"]; has_group {
            _index_proc_group(db, file_path, group, pkg, lines)
            continue
        }
        if name_node, has_proc := m.captures["proc_name"]; has_proc {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt          := ts_node_start_point(name_node)
            line        := int(pt.row) + 1
            qualified   := fmt.tprintf("%s::%s", pkg, name)
            is_exported := !proc_node_is_private(name_node, lines)
            sig         := _extract_proc_signature(name_node, lines)
            rt          := _extract_return_type(sig)
            proc_id := graph_insert_node(db, name, qualified, "function", file_path, line, sig, is_exported,
                end_line    = _decl_end_line(m.captures["proc_decl"], line),
                start_col   = int(pt.column),
                end_col     = int(ts_node_end_point(name_node).column),
                return_type = rt)
            if decl, has_decl := m.captures["proc_decl"]; has_decl && proc_id >= 0 {
                own := ownership_analyze(decl, lines)
                graph_record_ownership(db, proc_id, own.free_calls, own.sites[:], own.sinks[:], own.defaults[:], own.effects[:])
            }
            continue
        }
        // struct / bit_field -> "struct", union -> "union"
        type_kind := ""
        type_node: TSNode
        if n, has := m.captures["struct_name"]; has { type_kind = "struct"; type_node = n }
        if n, has := m.captures["bitfield_name"]; has { type_kind = "struct"; type_node = n }
        if n, has := m.captures["union_name"]; has { type_kind = "union"; type_node = n }
        if type_kind != "" {
            name := naming_extract_text(type_node, lines)
            if name == "" { continue }
            pt        := ts_node_start_point(type_node)
            line      := int(pt.row) + 1
            qualified := fmt.tprintf("%s::%s", pkg, name)
            graph_insert_node(db, name, qualified, type_kind, file_path, line, "", true,
                end_line  = _decl_end_line(m.captures["type_decl"], line),
                start_col = int(pt.column),
                end_col   = int(ts_node_end_point(type_node).column))
            continue
        }
        if name_node, has_enum := m.captures["enum_name"]; has_enum {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt   := ts_node_start_point(name_node)
            line := int(pt.row) + 1

            // Distinguish the enum TYPE NAME from member identifiers:
            // The type name appears before "::" on its line; members do not.
            is_type_name := false
            if int(pt.row) < len(lines) {
                src_line := lines[pt.row]
                dc := strings.index(src_line, "::")
                is_type_name = dc >= 0 && int(pt.column) < dc
            }
            if !is_type_name { continue } // skip member captures

            qualified := fmt.tprintf("%s::%s", pkg, name)
            node_id   := graph_insert_node(db, name, qualified, "enum", file_path, line, "", true,
                end_line  = _decl_end_line(m.captures["type_decl"], line),
                start_col = int(pt.column),
                end_col   = int(ts_node_end_point(name_node).column))
            if node_id >= 0 {
                _extract_enum_members(db, node_id, name_node, lines)
            }
            continue
        }
        if path_node, has_import := m.captures["import_path"]; has_import {
            path_raw := _extract_string_literal(path_node, lines)
            if path_raw == "" { continue }
            pt   := ts_node_start_point(path_node)
            line := int(pt.row) + 1
            graph_insert_node(db, path_raw, path_raw, "import", file_path, line, "", false,
                end_line  = _decl_end_line(m.captures["import_decl"], line),
                start_col = int(pt.column))

            // `import alias "path"`: an identifier directly under the declaration is the alias.
            alias := ""
            if decl, has_decl := m.captures["import_decl"]; has_decl {
                for i: u32 = 0; i < ts_node_child_count(decl); i += 1 {
                    c := ts_node_child(decl, i)
                    if string(ts_node_type(c)) == "identifier" {
                        alias = naming_extract_text(c, lines)
                        break
                    }
                }
            }
            graph_add_import(db, file_path, path_raw, alias, line)
            continue
        }
        if name_node, has_const := m.captures["const_name"]; has_const {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt   := ts_node_start_point(name_node)
            end  := ts_node_end_point(name_node)
            // Skip identifiers on the value side of :: (they're not the const name)
            if int(pt.row) < len(lines) {
                src_line := lines[pt.row]
                dc := strings.index(src_line, "::")
                if dc < 0 || int(end.column) > dc { continue }
            }
            line        := int(pt.row) + 1
            qualified   := fmt.tprintf("%s::%s", pkg, name)
            is_exported := !decl_node_is_private(name_node, lines)
            graph_insert_node(db, name, qualified, "constant", file_path, line, "", is_exported,
                end_line  = _decl_end_line(m.captures["const_decl"], line),
                start_col = int(pt.column),
                end_col   = int(end.column))
            continue
        }
        if name_node, has_var := m.captures["var_name"]; has_var {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt   := ts_node_start_point(name_node)
            end  := ts_node_end_point(name_node)
            // Skip identifiers on the type/value side of : (they're not the var name)
            if int(pt.row) < len(lines) {
                src_line := lines[pt.row]
                colon := strings.index(src_line, ":")
                if colon < 0 || int(end.column) > colon { continue }
            }
            line        := int(pt.row) + 1
            qualified   := fmt.tprintf("%s::%s", pkg, name)
            is_exported := !decl_node_is_private(name_node, lines)
            node_id     := graph_insert_node(db, name, qualified, "variable", file_path, line, "", is_exported,
                end_line  = _decl_end_line(m.captures["var_decl"], line),
                start_col = int(pt.column),
                end_col   = int(end.column))
            // Tag explicit allocator-typed package variables (e.g. "scratch: mem.Allocator")
            if node_id >= 0 && int(pt.row) < len(lines) {
                src_line := lines[pt.row]
                if strings.contains(src_line, "mem.Allocator") ||
                   strings.contains(src_line, "runtime.Allocator") {
                    graph_update_memory_role(db, node_id, "allocator")
                }
            }
            continue
        }
        if name_node, has_pkg_var := m.captures["pkg_var"]; has_pkg_var {
            // variable_declaration is only at package scope (:= at top level)
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt   := ts_node_start_point(name_node)
            end  := ts_node_end_point(name_node)
            // Skip identifiers on the RHS of :=
            if int(pt.row) < len(lines) {
                src_line := lines[pt.row]
                dc := strings.index(src_line, ":=")
                if dc < 0 || int(end.column) > dc { continue }
            }
            line        := int(pt.row) + 1
            qualified   := fmt.tprintf("%s::%s", pkg, name)
            is_exported := !decl_node_is_private(name_node, lines)
            graph_insert_node(db, name, qualified, "variable", file_path, line, "", is_exported,
                end_line  = _decl_end_line(m.captures["pkg_var_decl"], line),
                start_col = int(pt.column),
                end_col   = int(end.column))
            continue
        }
    }
}

// =============================================================================
// Pass 2 — Call resolution
// =============================================================================

// CallShape is how a call names its target.
@(private)
CallShape :: enum {
    Bare,       // f(x)            a name in the caller's own package
    Qualified,  // pkg.f(x)        `pkg` names an import, or else it is a value (a member call)
    Member,     // a.b.f(x)        a call through some value
    Selector,   // obj->f(x)       a procedure field called with obj as its receiver
}

// _classify_call looks at where a call sits. The grammar parses `pkg.f(x)` as a
// member_expression whose last child is the call, so the callee identifier alone
// cannot tell `f(x)` from `pkg.f(x)`: only the parent can.
@(private)
_classify_call :: proc(callee: TSNode, lines: []string) -> (shape: CallShape, qualifier: string) {
    call := ts_node_parent(callee)
    if ts_node_is_null(call) { return .Bare, "" }
    parent := ts_node_parent(call)
    if ts_node_is_null(parent) { return .Bare, "" }
    n := ts_node_child_count(parent)
    if n < 2 { return .Bare, "" }
    first := ts_node_child(parent, 0)
    last  := ts_node_child(parent, n - 1)
    // The call must be the trailing operand (`a.f()`), not merely a part (`f().a`).
    if ts_node_start_byte(last) != ts_node_start_byte(call) { return .Bare, "" }

    switch string(ts_node_type(parent)) {
    case "member_expression":
        if string(ts_node_type(first)) == "identifier" {
            return .Qualified, naming_extract_text(first, lines)
        }
        return .Member, naming_extract_text(first, lines)
    case "selector_call_expression":
        return .Selector, naming_extract_text(first, lines)
    }
    return .Bare, ""
}

@(private)
_pass2_resolve_calls :: proc(
    db:        ^GraphDB,
    file_path: string,
    root:      TSNode,
    lines:     []string,
    q:         ^CompiledQuery,
) {
    matches := run_query(q, root, lines)
    defer free_query_results(matches)

    // A bare name in Odin can only refer to something in the caller's own
    // package, and a package is a directory.
    pkg_dir   := graph_dir_of(graph_rel(db, file_path))
    file_node := graph_file_node(db, file_path)

    for &m in matches {
        callee_node, has_callee := m.captures["callee"]
        if !has_callee { continue }

        callee_name := naming_extract_text(callee_node, lines)
        if callee_name == "" { continue }

        shape, qualifier := _classify_call(callee_node, lines)
        // Builtins (make, len, ...) are only builtins as bare names.
        if shape == .Bare && _is_builtin(callee_name) { continue }

        call_pt   := ts_node_start_point(callee_node)
        call_line := int(call_pt.row) + 1
        call_col  := int(call_pt.column)

        // Innermost procedure that contains the call; a call outside every
        // procedure (a package-level initialiser) belongs to the file.
        caller_id := _find_enclosing_proc(db, file_path, call_line)
        if caller_id < 0 { caller_id = file_node }
        if caller_id < 0 { continue }

        callee_id: i64 = -1
        unresolved_name := callee_name
        switch shape {
        case .Bare:
            callee_id = graph_find_node_in_package(db, callee_name, pkg_dir)
        case .Qualified:
            dir, internal, found := graph_resolve_qualifier(db, file_path, qualifier)
            if found && internal {
                callee_id = graph_find_node_in_package(db, callee_name, dir)
                delete(dir)
            }
            // An import we cannot see into (core:fmt) or a package that lacks the
            // name stays "pkg::name"; a qualifier that is no import is a value.
            unresolved_name = fmt.tprintf("%s::%s" if found else "%s.%s", qualifier, callee_name)
        case .Member:
            unresolved_name = fmt.tprintf("%s.%s", qualifier, callee_name)
        case .Selector:
            unresolved_name = fmt.tprintf("%s->%s", qualifier, callee_name)
        }

        if callee_id < 0 {
            graph_insert_unresolved(db, caller_id, unresolved_name, "calls", file_path, call_line, call_col)
            continue
        }
        graph_insert_edge(db, caller_id, callee_id, "calls", call_line, call_col)
    }
}

// _find_enclosing_proc returns the handle of the innermost procedure whose
// span contains line, or -1. (The span check matters: "the last procedure that
// started before this line" mis-attributes every call after a nested procedure ends.)
@(private)
_find_enclosing_proc :: proc(db: ^GraphDB, file: string, line: int) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        `SELECT rowid FROM nodes
         WHERE file_path=?1 AND kind='function' AND start_line<=?2 AND end_line>=?2
         ORDER BY start_line DESC, start_column DESC LIMIT 1;`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, graph_rel(db, file))
    sq.stmt_bind_int(&s, 2, line)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// =============================================================================
// Pass 2b — Ownership across procedure boundaries
// =============================================================================

// _cross_signature summarises which procedures are factories or sinks, to see when a round
// of re-analysis has found nothing new.
@(private)
_cross_signature :: proc(f: map[i64]FactoryRow, s, keeps, reads: map[i64]u64) -> u64 {
    sig := u64(len(f)) * 1_000_003 + u64(len(s)) + u64(len(keeps)) * 7_919 + u64(len(reads)) * 104_729
    for h in f { sig += u64(h) * 31 }
    for h, mask in s { sig += u64(h) * 17 + mask * 7 }
    for h, mask in keeps { sig += u64(h) * 13 + mask * 5 }
    for h, mask in reads { sig += u64(h) * 11 + mask * 3 }
    return sig
}

@(private)
_collect_proc_decls :: proc(n: TSNode, out: ^[dynamic]TSNode) {
    if string(ts_node_type(n)) == "procedure_declaration" { append(out, n) }
    for i in 0 ..< int(ts_node_child_count(n)) {
        _collect_proc_decls(ts_node_child(n, u32(i)), out)
    }
}

// _pass2b_cross_ownership re-reads the procedures that call a factory (a procedure that
// returns memory it allocated) or a sink (one that frees a parameter), so that
//   t := make_thing()      is an allocation owned by the caller, and
//   consume(n)             frees n when consume frees its parameter.
// What a procedure returns or frees can itself depend on such a call (a wrapper around a
// factory is a factory), so it repeats until the sets stop growing.
@(private)
_pass2b_cross_ownership :: proc(db: ^GraphDB, ts_parser: ^TreeSitterASTParser) {
    prev: u64
    for round in 0 ..< 6 {
        factories := graph_load_factories(db)
        sinks     := graph_load_sinks(db)
        keeps, reads := graph_load_param_effects(db)
        sig       := _cross_signature(factories, sinks, keeps, reads)
        if round > 0 && sig == prev {
            graph_free_factories(factories); delete(sinks); delete(keeps); delete(reads)
            return
        }
        prev = sig

        rows  := graph_load_call_rows(db)
        infos := make(map[string]CrossInfo)
        for r in rows {
            fac, is_fac := factories[r.callee]
            mask := sinks[r.callee]
            keep, read := keeps[r.callee], reads[r.callee]
            if !is_fac && mask == 0 && keep == 0 && read == 0 { continue }
            info, has := infos[r.file]
            if !has { info = CrossInfo{ calls = make(map[[2]int]CrossCall) } }
            cc := CrossCall{ sink_mask = mask, keep_mask = keep, read_mask = read }
            if is_fac {
                cc.name = fac.name; cc.callee = r.callee; cc.factory = true; cc.factory_kind = fac.kind; cc.elem_type = fac.elem_type; cc.default_kind = fac.default_kind
            }
            info.calls[{r.line, r.col}] = cc
            infos[r.file] = info
        }
        // files that held call-based sites before must be re-read even if nothing calls a factory now
        stale := graph_files_with_call_sites(db)
        for f in stale { if !(f in infos) { infos[strings.clone(f)] = CrossInfo{ calls = make(map[[2]int]CrossCall) } } }

        for file, &info in infos {
            _reanalyze_file(db, ts_parser, file, &info)
        }

        for r in rows { delete(r.file) }
        delete(rows)
        for f in stale { delete(f) }
        delete(stale)
        for f, info in infos { delete(info.calls); _ = f }
        delete(infos)
        graph_free_factories(factories); delete(sinks); delete(keeps); delete(reads)
    }
}

@(private)
_reanalyze_file :: proc(db: ^GraphDB, ts_parser: ^TreeSitterASTParser, rel_file: string, info: ^CrossInfo) {
    abs := graph_abs(db, rel_file)
    defer delete(abs)
    content, err := os.read_entire_file_from_path(abs, context.allocator)
    if err != nil { return }
    defer delete(content)
    lines := strings.split(string(content), "\n")
    defer delete(lines)

    tree, ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, string(content))
    if !ok { return }
    defer ts_tree_delete(tree)
    root := getRootNode(tree)
    if ts_node_is_null(root) { return }

    decls := make([dynamic]TSNode)
    defer delete(decls)
    _collect_proc_decls(root, &decls)

    for decl in decls {
        guard := runtime.default_temp_allocator_temp_begin()
        defer runtime.default_temp_allocator_temp_end(guard)

        name_pt: TSPoint
        found := false
        for i in 0 ..< int(ts_node_child_count(decl)) {
            c := ts_node_child(decl, u32(i))
            if string(ts_node_type(c)) == "identifier" { name_pt = ts_node_start_point(c); found = true; break }
        }
        if !found { continue }
        id := graph_find_function_at(db, abs, int(name_pt.row) + 1, int(name_pt.column))
        if id < 0 { continue }
        own := ownership_analyze(decl, lines, info)
        graph_record_ownership(db, id, own.free_calls, own.sites[:], own.sinks[:], own.defaults[:], own.effects[:])
    }
}

// =============================================================================
// Pass 3 — Memory role tagging
// =============================================================================

@(private)
_pass3_tag_memory_roles :: proc(db: ^GraphDB) {
    s, ok := sq.db_prepare(db.conn, `SELECT rowid, COALESCE(return_type,'') FROM nodes WHERE kind='function';`)
    if !ok { return }
    defer sq.stmt_finalize(&s)

    ids          := make([dynamic]i64)
    return_types := make([dynamic]string)
    defer { delete(ids); for rt in return_types { delete(rt) }; delete(return_types) }

    for sq.stmt_step(&s) {
        append(&ids,          sq.stmt_col_i64(&s, 0))
        append(&return_types, sq.stmt_col_text(&s, 1))
    }

    for i in 0..<len(ids) {
        // Procs that return an allocator type are themselves allocator factories.
        if strings.contains(return_types[i], "Allocator") {
            graph_update_memory_role(db, ids[i], "allocator")
            continue
        }
        role := _infer_role(db, ids[i])
        graph_update_memory_role(db, ids[i], role)
    }
}

// _infer_role guesses what a procedure does with memory. It prefers the facts the
// ownership analysis recorded (allocation sites and what became of them) and falls back to
// the names of the procedures it calls, for code whose allocation is hidden behind helpers.
//
//   allocator    hands memory on: a site is returned, stored or passed, or is left unfreed
//                from the default or a parameter allocator (temp and arena memory owes nothing)
//   borrower     allocates and frees within itself
//   deallocator  frees but allocates nothing
//   neutral      none of the above
@(private)
_infer_role :: proc(db: ^GraphDB, node_id: i64) -> string {
    sites, free_calls := 0, 0
    escaping, contained := 0, 0
    st, st_ok := sq.db_prepare(db.conn,
        `SELECT COALESCE(o.alloc_sites,0),
                COALESCE(o.free_calls,0) + (SELECT COUNT(*) FROM odin_param_sink k WHERE k.proc_id = n.id)
         FROM nodes n LEFT JOIN odin_proc_ownership o ON o.proc_id = n.id WHERE n.rowid=?;`)
    if st_ok {
        sq.stmt_bind_i64(&st, 1, node_id)
        if sq.stmt_step(&st) {
            sites      = sq.stmt_col_int(&st, 0)
            free_calls = sq.stmt_col_int(&st, 1)
        }
        sq.stmt_finalize(&st)
    }
    if sites > 0 {
        ss, ss_ok := sq.db_prepare(db.conn,
            `SELECT a.allocator_kind, a.disposition, ` + SQL_UNPROVEN_FACTORY_CALL + `
             FROM odin_alloc_site a JOIN nodes n ON n.id = a.proc_id WHERE n.rowid=?;`)
        if ss_ok {
            sq.stmt_bind_i64(&ss, 1, node_id)
            for sq.stmt_step(&ss) {
                kind := sq.stmt_col_text(&ss, 0)
                disp := sq.stmt_col_text(&ss, 1)
                unproven := sq.stmt_col_int(&ss, 2) != 0
                switch {
                case disp == "freed" || disp == "freed_deferred":
                    contained += 1
                case kind == "temp":
                    // released wholesale: nothing is owed
                case disp == "unfreed" && kind == "custom":
                    // an arena (or a reassigned context.allocator) releases it
                case disp == "unfreed" && unproven:
                    // nobody releases what that factory returns: the project does not, by convention
                case:
                    escaping += 1
                }
                delete(kind); delete(disp)
            }
            sq.stmt_finalize(&ss)
        }
        if escaping  > 0 { return "allocator" }
        if contained > 0 { return "borrower"  }
    }
    if sites == 0 && free_calls > 0 { return "deallocator" }

    // Fallback: the names of what this procedure calls, matched as whole words.
    calls_alloc, calls_free := false, false
    s, ok := sq.db_prepare(db.conn,
        `SELECT n.name FROM edges e JOIN nodes n ON e.target=n.id
         WHERE e.source=(SELECT id FROM nodes WHERE rowid=?) AND e.kind='calls';`)
    if !ok { return "neutral" }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)
    for sq.stmt_step(&s) {
        callee := sq.stmt_col_text(&s, 0)
        defer delete(callee)
        switch callee {
        case "delete_key", "delete_elem", "delete_at": continue
        }
        for tok in strings.split(callee, "_", context.temp_allocator) {
            switch tok {
            case "make", "new", "alloc", "create": calls_alloc = true
            case "free", "delete", "destroy", "release": calls_free = true
            }
        }
    }
    if sites == 0 {
        if calls_alloc && !calls_free { return "allocator"   }
        if calls_free  && !calls_alloc { return "deallocator" }
        if calls_alloc &&  calls_free  { return "borrower"    }
    }
    return "neutral"
}

// =============================================================================
// Pass 4 — Lint violations
// =============================================================================

@(private)
_pass4_attach_violations :: proc(
    db:        ^GraphDB,
    files:     []string,
    ts_parser: ^TreeSitterASTParser,
    opts:      LintOptions,
) {
    // Compile SCM queries once; reuse across all files.
    lang := ts_parser.adapter.language
    q_c002, q_c002_ok := load_query_src(lang, MEMORY_SAFETY_SCM,     "memory_safety.scm")
    q_c003, q_c003_ok := load_query_src(lang, NAMING_RULES_SCM,      "naming_rules.scm")
    q_c009, q_c009_ok := load_query_src(lang, ODIN2026_SCM,          "odin2026_migration.scm")
    q_c011, q_c011_ok := load_query_src(lang, FFI_SAFETY_SCM,        "ffi_safety.scm")
    q_c201, q_c201_ok := load_query_src(lang, UNCHECKED_RESULT_SCM,  "unchecked_result.scm")
    defer if q_c002_ok { unload_query(&q_c002) }
    defer if q_c003_ok { unload_query(&q_c003) }
    defer if q_c009_ok { unload_query(&q_c009) }
    defer if q_c011_ok { unload_query(&q_c011) }
    defer if q_c201_ok { unload_query(&q_c201) }

    // TypeResolveContext for C201: use graph DB (procs already indexed in Pass 1+2).
    type_ctx := TypeResolveContext{db = db}

    for file_path in files {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil { continue }
        src := string(content)

        collector := make([dynamic]Diagnostic)

        // C001 + C101 — AST walker rules (share one parse)
        ast_root, ast_ok := parseToAST(ts_parser.adapter, src)
        if ast_ok {
            lines := strings.split(src, "\n")
            for d in dedupDiagnostics(c001_matcher(file_path, &ast_root, lines, true)) {
                if d.diag_type != .NONE && d.diag_type != .INTERNAL_ERROR {
                    append(&collector, d)
                }
            }
            for d in dedupDiagnostics(c101_run(file_path, &ast_root, lines)) {
                append(&collector, d)
            }
            delete(lines)
        }

        // SCM + AST-walk rules — parse tree-sitter once, run all queries
        tree, tree_ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, src)
        if tree_ok {
            root  := getRootNode(tree)
            lines := strings.split(src, "\n")
            if !ts_node_is_null(root) {
                if q_c002_ok {
                    for d in dedupDiagnostics(c002_scm_matcher(file_path, root, lines, &q_c002)) {
                        append(&collector, d)
                    }
                }
                if q_c003_ok {
                    for d in dedupDiagnostics(naming_scm_run(file_path, root, lines, &q_c003, NAMING_ALL_ENABLED)) {
                        append(&collector, d)
                    }
                }
                if q_c009_ok {
                    for d in dedupDiagnostics(c009_scm_run(file_path, root, lines, &q_c009)) {
                        append(&collector, d)
                    }
                    for d in dedupDiagnostics(c010_scm_run(file_path, root, lines, &q_c009)) {
                        append(&collector, d)
                    }
                }
                if q_c011_ok {
                    for d in dedupDiagnostics(c011_scm_run(file_path, root, lines, &q_c011)) {
                        append(&collector, d)
                    }
                }
                if q_c201_ok {
                    for d in dedupDiagnostics(c201_scm_run(file_path, root, lines, &q_c201, &type_ctx)) {
                        append(&collector, d)
                    }
                }
                // C203 — pure AST walker, no SCM query needed
                for d in dedupDiagnostics(c203_run(file_path, root, lines)) {
                    append(&collector, d)
                }
            }
            delete(lines)
            ts_tree_delete(tree)
        }
        delete(content)

        if len(collector) == 0 { delete(collector); continue }

        for d in collector {
            node_id := _find_enclosing_proc(db, file_path, d.line)
            if node_id < 0 { continue }

            vs, vok := sq.db_prepare(db.conn,
                `SELECT COALESCE(lint_violations,'') FROM odin_node_info
                 WHERE node_id=(SELECT id FROM nodes WHERE rowid=?);`)
            if !vok { continue }
            sq.stmt_bind_i64(&vs, 1, node_id)
            existing := ""
            if sq.stmt_step(&vs) { existing = sq.stmt_col_text(&vs, 0) }
            sq.stmt_finalize(&vs)

            new_json: string
            if existing == "" || existing == "null" {
                new_json = fmt.tprintf(`["%s"]`, d.rule_id)
            } else {
                trimmed := strings.trim_right(existing, "]")
                new_json = fmt.tprintf(`%s,"%s"]`, trimmed, d.rule_id)
            }
            graph_update_violations(db, node_id, new_json)
            delete(existing)
        }
        delete(collector)
    }
}

// =============================================================================
// Pass 5 — symbols.json
// =============================================================================

@(private)
_pass5_write_symbols_json :: proc(db: ^GraphDB, out_path: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    strings.write_string(&sb, `{"schema_version":"odin-lint-symbols/1.1","procedures":[`)

    s, ok := sq.db_prepare(db.conn,
        `SELECT n.rowid, n.name, n.file_path, n.start_line,
                COALESCE(i.memory_role,''), COALESCE(i.lint_violations,''),
                COALESCE(n.signature,''), COALESCE(n.return_type,'')
         FROM nodes n LEFT JOIN odin_node_info i ON i.node_id = n.id
         WHERE n.kind='function' ORDER BY n.file_path, n.start_line;`)
    if !ok { return }
    defer sq.stmt_finalize(&s)

    first := true
    for sq.stmt_step(&s) {

        id   := sq.stmt_col_i64(&s, 0)
        name := sq.stmt_col_text(&s, 1)
        file_rel := sq.stmt_col_text(&s, 2)
        file     := graph_abs(db, file_rel)
        delete(file_rel)
        line := sq.stmt_col_int(&s, 3)
        role_raw := sq.stmt_col_text(&s, 4)
        violations_raw := sq.stmt_col_text(&s, 5)
        sig     := sq.stmt_col_text(&s, 6)
        ret_raw := sq.stmt_col_text(&s, 7)

        // Use display values (may be literals); always delete the owned raw copies.
        role_str       := role_raw       if role_raw       != "" else "neutral"
        violations_str := violations_raw if violations_raw != "" else "[]"

        callers := graph_get_callers(db, id)
        callees := graph_get_callees(db, id)

        if !first { strings.write_string(&sb, ",") }
        first = false

        strings.write_string(&sb, `{"name":`)
        strings.write_string(&sb, _json_str(name))
        strings.write_string(&sb, `,"file":`)
        strings.write_string(&sb, _json_str(file))
        fmt.sbprintf(&sb, `,"line":%d,"memory_role":`, line)
        strings.write_string(&sb, _json_str(role_str))
        strings.write_string(&sb, `,"signature":`)
        strings.write_string(&sb, _json_str(sig))
        strings.write_string(&sb, `,"return_type":`)
        strings.write_string(&sb, _json_str(ret_raw))
        strings.write_string(&sb, `,"lint_violations":`)
        strings.write_string(&sb, violations_str)

        strings.write_string(&sb, `,"callers":[`)
        for n, idx in callers {
            if idx > 0 { strings.write_string(&sb, ",") }
            fmt.sbprintf(&sb, "%s", _json_str(n.name))
        }
        strings.write_string(&sb, `],"callees":[`)
        for n, idx in callees {
            if idx > 0 { strings.write_string(&sb, ",") }
            fmt.sbprintf(&sb, "%s", _json_str(n.name))
        }
        strings.write_string(&sb, `]}`)

        for n in callers { delete(n.name); delete(n.kind); delete(n.file); delete(n.memory_role); delete(n.lint_violations); delete(n.signature); delete(n.return_type) }
        delete(callers)
        for n in callees { delete(n.name); delete(n.kind); delete(n.file); delete(n.memory_role); delete(n.lint_violations); delete(n.signature); delete(n.return_type) }
        delete(callees)

        delete(name)
        delete(file)
        delete(role_raw)
        delete(violations_raw)
        delete(sig)
        delete(ret_raw)
    }

    strings.write_string(&sb, `]}`)

    _ = os.write_entire_file(out_path, transmute([]u8)strings.to_string(sb))
}

// =============================================================================
// Utilities
// =============================================================================

@(private)
_extract_string_literal :: proc(node: TSNode, lines: []string) -> string {
    pt      := ts_node_start_point(node)
    end_pt  := ts_node_end_point(node)
    line_idx := int(pt.row)
    if line_idx < 0 || line_idx >= len(lines) { return "" }
    line      := lines[line_idx]
    col_start := int(pt.column)
    col_end   := int(end_pt.column)
    if col_start >= len(line) { return "" }
    if col_end > len(line) { col_end = len(line) }
    raw := line[col_start:col_end]
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        return raw[1 : len(raw)-1]
    }
    return raw
}

@(private)
_package_from_path :: proc(file_path: string) -> string {
    path := file_path
    for i := len(path) - 1; i >= 0; i -= 1 {
        if path[i] == '/' { path = path[:i]; break }
    }
    for i := len(path) - 1; i >= 0; i -= 1 {
        if path[i] == '/' { return path[i+1:] }
    }
    return path
}

@(private)
_is_builtin :: proc(name: string) -> bool {
    builtins := []string{
        "make", "new", "free", "delete", "append", "len", "cap",
        "copy", "clear", "map", "cast", "auto_cast", "transmute",
        "size_of", "align_of", "offset_of", "type_of", "typeid_of",
        "min", "max", "abs", "clamp", "swizzle",
        "print", "println", "printf", "eprint", "eprintln", "eprintfln",
        "panic", "assert", "unimplemented", "unreachable",
    }
    for b in builtins { if name == b { return true } }
    return false
}

@(private)
_json_str :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    strings.write_byte(&sb, '"')
    for c in s {
        switch c {
        case '"':  strings.write_string(&sb, `\"`)
        case '\\': strings.write_string(&sb, `\\`)
        case '\n': strings.write_string(&sb, `\n`)
        case '\r': strings.write_string(&sb, `\r`)
        case '\t': strings.write_string(&sb, `\t`)
        case:
            if c < 0x20 {
                fmt.sbprintf(&sb, `\u%04x`, int(c))
            } else {
                strings.write_rune(&sb, c)
            }
        }
    }
    strings.write_byte(&sb, '"')
    return strings.to_string(sb)
}

// _extract_proc_signature returns the text from the proc_name position up to (but
// not including) the opening '{' of the proc body, collapsed to a single line.
// Scans at most 10 lines to handle multi-line parameter lists.
@(private)
_extract_proc_signature :: proc(name_node: TSNode, lines: []string) -> string {
    pt         := ts_node_start_point(name_node)
    start_line := int(pt.row)

    sb := strings.builder_make(context.temp_allocator)
    for i := start_line; i < len(lines) && i < start_line+10; i += 1 {
        line := lines[i]
        brace := strings.index(line, "{")
        if brace >= 0 {
            strings.write_string(&sb, line[:brace])
            break
        }
        if i > start_line { strings.write_byte(&sb, ' ') }
        strings.write_string(&sb, line)
    }
    return strings.trim_space(strings.to_string(sb))
}

// _extract_return_type parses the `->` portion of a proc signature string.
// Returns the trimmed return type, or "" if no `->` is present.
@(private)
_extract_return_type :: proc(sig: string) -> string {
    arrow := strings.last_index(sig, "->")
    if arrow < 0 { return "" }
    return strings.trim_space(sig[arrow+2:])
}

@(private)
_count_table :: proc(db: ^GraphDB, table: string) -> int {
    sql  := fmt.tprintf("SELECT COUNT(*) FROM %s;", table)
    s, ok := sq.db_prepare(db.conn, sql)
    if !ok { return 0 }
    defer sq.stmt_finalize(&s)
    if sq.stmt_step(&s) { return sq.stmt_col_int(&s, 0) }
    return 0
}

// _extract_enum_members collects enum field names from an enum_declaration node.
//
// In the Odin tree-sitter grammar, enum members are DIRECT children of
// enum_declaration alongside the type name identifier. The structure is:
//
//   enum_declaration
//     identifier  "DiagnosticType"   ← the type name (== name_node; skip)
//     identifier  "NONE"             ← member
//     identifier  "VIOLATION"        ← member
//     binary_expression              ← member with explicit value (Red = 1)
//       identifier "Red"
//
// We skip the first identifier (which is name_node itself) and collect all
// subsequent identifiers and the leading identifier of binary_expressions.
@(private)
_extract_enum_members :: proc(db: ^GraphDB, enum_node_id: i64, name_node: TSNode, lines: []string) {
    parent := ts_node_parent(name_node)
    if ts_node_is_null(parent) { return }

    // Get the position of the type name so we can skip it.
    name_pt  := ts_node_start_point(name_node)
    name_row := int(name_pt.row)
    name_col := int(name_pt.column)

    member_idx := 0
    n := ts_node_child_count(parent)
    for i: u32 = 0; i < n; i += 1 {
        child := ts_node_child(parent, i)
        if ts_node_is_null(child) { continue }

        child_type := string(ts_node_type(child))
        switch child_type {
        case "identifier":
            // Skip the type name itself (same position as name_node).
            cpt := ts_node_start_point(child)
            if int(cpt.row) == name_row && int(cpt.column) == name_col { continue }
            member_name := naming_extract_text(child, lines)
            if member_name != "" {
                graph_insert_enum_member(db, enum_node_id, member_name, member_idx, int(cpt.row) + 1)
                member_idx += 1
            }
        case "binary_expression":
            // Explicit value: Red = 1 — first child is the member identifier.
            if ts_node_child_count(child) > 0 {
                first := ts_node_child(child, 0)
                if !ts_node_is_null(first) && string(ts_node_type(first)) == "identifier" {
                    member_name := naming_extract_text(first, lines)
                    if member_name != "" {
                        graph_insert_enum_member(db, enum_node_id, member_name, member_idx, int(ts_node_start_point(first).row) + 1)
                        member_idx += 1
                    }
                }
            }
        }
    }
}
