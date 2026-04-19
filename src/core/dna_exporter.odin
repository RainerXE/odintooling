package core

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import sq "../../vendor/odin-sqlite3"

// Default output location relative to the project root.
GRAPH_DB_PATH     :: ".codegraph/odin_lint_graph.db"
SYMBOLS_JSON_PATH :: ".codegraph/symbols.json"

// ExportResult summarises what the exporter produced.
ExportResult :: struct {
    files_indexed: int,
    nodes_written: int,
    edges_written: int,
    unresolved:    int,
    db_path:       string,
    symbols_path:  string,
    ok:            bool,
}

// export_symbols runs the full 5-pass DNA export pipeline.
// paths: the same target list accepted by the CLI (files or directories).
// db_path: where to write the SQLite graph (defaults to GRAPH_DB_PATH).
export_symbols :: proc(
    paths:     []string,
    ts_parser: ^TreeSitterASTParser,
    db_path:   string = GRAPH_DB_PATH,
) -> ExportResult {
    result := ExportResult{db_path = db_path, symbols_path = SYMBOLS_JSON_PATH}

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

    graph_clear(db)

    files := collect_odin_files(paths, true, false)
    defer {
        for f in files { delete(f) }
        delete(files)
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

    for file_path in files {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil { continue }

        now_ts := i64(time.now()._nsec / 1_000_000_000)
        graph_insert_file(db, file_path, fmt.tprintf("%d", len(content)), now_ts)

        lines := strings.split(string(content), "\n")

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
    // Pass 5 — Write symbols.json.
    // -----------------------------------------------------------------------
    _pass5_write_symbols_json(db, SYMBOLS_JSON_PATH)

    result.nodes_written = _count_table(db, "nodes")
    result.edges_written = _count_table(db, "edges")
    result.unresolved    = _count_table(db, "unresolved_refs")
    result.ok = true
    return result
}

// =============================================================================
// Pass 1 — Declarations
// =============================================================================

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

    for &m in matches {
        if name_node, has_proc := m.captures["proc_name"]; has_proc {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt        := ts_node_start_point(name_node)
            line      := int(pt.row) + 1
            qualified := fmt.tprintf("%s.%s", _package_from_path(file_path), name)
            graph_insert_node(db, name, qualified, "proc", file_path, line, "", true)
            continue
        }
        if name_node, has_struct := m.captures["struct_name"]; has_struct {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt        := ts_node_start_point(name_node)
            line      := int(pt.row) + 1
            qualified := fmt.tprintf("%s.%s", _package_from_path(file_path), name)
            graph_insert_node(db, name, qualified, "type", file_path, line, "", true)
            continue
        }
        if name_node, has_enum := m.captures["enum_name"]; has_enum {
            name := naming_extract_text(name_node, lines)
            if name == "" { continue }
            pt        := ts_node_start_point(name_node)
            line      := int(pt.row) + 1
            qualified := fmt.tprintf("%s.%s", _package_from_path(file_path), name)
            graph_insert_node(db, name, qualified, "type", file_path, line, "", true)
            continue
        }
        if path_node, has_import := m.captures["import_path"]; has_import {
            path_raw := _extract_string_literal(path_node, lines)
            if path_raw == "" { continue }
            pt   := ts_node_start_point(path_node)
            line := int(pt.row) + 1
            graph_insert_node(db, path_raw, path_raw, "import", file_path, line, "", false)
            continue
        }
    }
}

// =============================================================================
// Pass 2 — Call resolution
// =============================================================================

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

    for &m in matches {
        callee_node, has_callee := m.captures["callee"]
        if !has_callee { continue }

        callee_name := naming_extract_text(callee_node, lines)
        if callee_name == "" || _is_builtin(callee_name) { continue }

        call_pt   := ts_node_start_point(callee_node)
        call_line := int(call_pt.row) + 1

        callee_id := graph_find_node(db, callee_name)
        caller_id := _find_enclosing_proc(db, file_path, call_line)

        if callee_id < 0 {
            graph_insert_unresolved(db, caller_id, callee_name, "calls", file_path, call_line)
            continue
        }
        if caller_id < 0 { continue }

        graph_insert_edge(db, caller_id, callee_id, "calls", call_line)
    }
}

@(private)
_find_enclosing_proc :: proc(db: ^GraphDB, file: string, line: int) -> i64 {
    s, ok := sq.db_prepare(db.conn,
        `SELECT id FROM nodes WHERE file=? AND kind='proc' AND line<=? ORDER BY line DESC LIMIT 1;`)
    if !ok { return -1 }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_text(&s, 1, file)
    sq.stmt_bind_int(&s, 2, line)
    if sq.stmt_step(&s) { return sq.stmt_col_i64(&s, 0) }
    return -1
}

// =============================================================================
// Pass 3 — Memory role tagging
// =============================================================================

@(private)
_pass3_tag_memory_roles :: proc(db: ^GraphDB) {
    s, ok := sq.db_prepare(db.conn, `SELECT id FROM nodes WHERE kind='proc';`)
    if !ok { return }
    defer sq.stmt_finalize(&s)

    ids := make([dynamic]i64)
    defer delete(ids)
    for sq.stmt_step(&s) { append(&ids, sq.stmt_col_i64(&s, 0)) }

    for id in ids {
        role := _infer_role(db, id)
        graph_update_memory_role(db, id, role)
    }
}

@(private)
_infer_role :: proc(db: ^GraphDB, node_id: i64) -> string {
    alloc_names := []string{"make", "new", "alloc", "create"}
    free_names  := []string{"free", "delete", "destroy", "release"}

    calls_alloc := false
    calls_free  := false

    s, ok := sq.db_prepare(db.conn,
        `SELECT n.name FROM edges e JOIN nodes n ON e.target_id=n.id WHERE e.source_id=? AND e.kind='calls';`)
    if !ok { return "neutral" }
    defer sq.stmt_finalize(&s)
    sq.stmt_bind_i64(&s, 1, node_id)

    for sq.stmt_step(&s) {
        callee := sq.stmt_col_text(&s, 0)
        defer delete(callee)
        for a in alloc_names { if strings.contains(callee, a) { calls_alloc = true } }
        for f in free_names  { if strings.contains(callee, f) { calls_free  = true } }
    }

    if calls_alloc && !calls_free  { return "allocator"   }
    if calls_free  && !calls_alloc { return "deallocator" }
    if calls_alloc &&  calls_free  { return "borrower"    }
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
    for file_path in files {
        collector := make([dynamic]Diagnostic)
        defer delete(collector)

        analyze_file(file_path, ts_parser, opts, &collector)
        if len(collector) == 0 { continue }

        for d in collector {
            node_id := _find_enclosing_proc(db, file_path, d.line)
            if node_id < 0 { continue }

            vs, vok := sq.db_prepare(db.conn, `SELECT lint_violations FROM nodes WHERE id=?;`)
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
        }
    }
}

// =============================================================================
// Pass 5 — symbols.json
// =============================================================================

@(private)
_pass5_write_symbols_json :: proc(db: ^GraphDB, out_path: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    strings.write_string(&sb, `{"schema":"odin-lint-symbols/1.0","procedures":[`)

    s, ok := sq.db_prepare(db.conn,
        `SELECT id,name,file,line,memory_role,lint_violations,signature FROM nodes WHERE kind='proc';`)
    if !ok { return }
    defer sq.stmt_finalize(&s)

    first := true
    for sq.stmt_step(&s) {

        id   := sq.stmt_col_i64(&s, 0)
        name := sq.stmt_col_text(&s, 1)
        file := sq.stmt_col_text(&s, 2)
        line := sq.stmt_col_int(&s, 3)
        role_raw := sq.stmt_col_text(&s, 4)
        violations_raw := sq.stmt_col_text(&s, 5)
        sig  := sq.stmt_col_text(&s, 6)

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

        for n in callers { delete(n.name); delete(n.kind); delete(n.file); delete(n.memory_role); delete(n.lint_violations); delete(n.signature) }
        delete(callers)
        for n in callees { delete(n.name); delete(n.kind); delete(n.file); delete(n.memory_role); delete(n.lint_violations); delete(n.signature) }
        delete(callees)

        delete(name)
        delete(file)
        delete(role_raw)
        delete(violations_raw)
        delete(sig)
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
    if !strings.contains_any(s, `"\`) { return fmt.tprintf(`"%s"`, s) }
    e1, _ := strings.replace_all(s,  `\`, `\\`)
    e2, _ := strings.replace_all(e1, `"`, `\"`)
    return fmt.tprintf(`"%s"`, e2)
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
