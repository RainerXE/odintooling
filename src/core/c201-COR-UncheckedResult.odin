// c201-COR-UncheckedResult.odin — C201: unchecked error return value.
// SCM query finds bare call statements (not assigned) to procs that return an error
// or bool; uses the graph DB for project-local proc resolution beyond the stdlib list.
package core

import "core:fmt"
import "core:path/filepath"
import "core:strings"

// =============================================================================
// C201: Unchecked error return — bare call to a proc that returns an error
// =============================================================================
// Detects call_expression statements whose return value is discarded and
// whose proc is known to return an error type. Uses TypeResolveContext:
//   1. stdlib curated list
//   2. graph DB (return_type field)
//   3. the source of the package the call goes to (see type_resolver.odin)
//
// Parent-block filtering: a call_expression is "bare" (result discarded) only
// when its parent node is a block. Calls inside assignment_statement,
// return_statement, conditions, etc. are NOT flagged.
// Category: CORRECTNESS
// =============================================================================

c201_rule :: proc() -> Rule {
    return Rule{
        id       = "C201",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c201_message,
        fix_hint = c201_fix_hint,
    }
}

c201_message  :: proc() -> string { return "Error return value ignored — call result discarded" }
c201_fix_hint :: proc() -> string { return "Assign the result and handle the error, or use 'or_return'" }

c201_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
    type_ctx:   ^TypeResolveContext,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    // What this file imports, so a qualified call can be followed into the package it goes to.
    resolver_begin_run()
    if type_ctx != nil {
        type_ctx.file_dir = filepath.dir(file_path)
        type_ctx.imports  = _file_imports(root_node, file_lines)
        defer delete(type_ctx.imports)
    }

    suppressions := collect_suppressions(1, len(file_lines), file_lines)
    defer free_suppressions(suppressions)
    diagnostics  := make([dynamic]Diagnostic)

    seen := make(map[string]bool)
    defer delete(seen)

    for result in results {
        call_node, c_ok := result.captures["c201_call"]
        if !c_ok { continue }

        // Only flag bare calls: parent of call_expression must be a block.
        parent := ts_node_parent(call_node)
        if ts_node_is_null(parent) { continue }
        parent_type := string(ts_node_type(parent))
        // Qualified calls (os.open, net.dial_tcp, etc.) are parsed as:
        //   member_expression (parent=block)
        //     call_expression (parent=member_expression)  ← what we match
        // Plain calls (open, close, etc.) have call_expression directly in block.
        if parent_type == "member_expression" {
            gp := ts_node_parent(parent)
            if ts_node_is_null(gp) { continue }
            parent_type = string(ts_node_type(gp))
        }
        if parent_type != "block" { continue }

        // Extract the function name from the first child of the call_expression.
        // Structure: call_expression → [function_node, args...]
        // function_node is identifier (plain) or member_expression (qualified).
        fn_name := c201_extract_fn_name(call_node, file_lines)
        if len(fn_name) == 0 { continue }

        if !proc_returns_error(type_ctx, fn_name) { continue }

        pt  := ts_node_start_point(call_node)
        pos := Position{line = int(pt.row) + 1, col = int(pt.column) + 1}

        loc_key := fmt.tprintf("%d:%d", pos.line, pos.col)
        if seen[loc_key] { continue }
        seen[loc_key] = true

        if is_suppressed("C201", pos.line, suppressions) { continue }

        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = pos.line,
            column    = pos.col,
            rule_id   = "C201",
            tier      = "correctness",
            message   = fmt.aprintf("error return of '%s' is discarded", fn_name),
            has_fix   = true,
            fix       = "Assign the result and handle the error, or use 'or_return'",
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}

// _line_text is the text of a node that sits on one line (an identifier, an import path).
@(private="file")
_line_text :: proc(n: TSNode, lines: []string) -> string {
    sp, ep := ts_node_start_point(n), ts_node_end_point(n)
    row := int(sp.row)
    if row < 0 || row >= len(lines) || ep.row != sp.row { return "" }
    line := lines[row]
    c0, c1 := int(sp.column), min(int(ep.column), len(line))
    if c0 > c1 { return "" }
    return line[c0:c1]
}

// _file_imports lists a file's imports as the name a qualifier uses -> the import path:
// `import "core:os"` gives os, `import fp "core:path/filepath"` gives fp.
@(private="file")
_file_imports :: proc(root: TSNode, lines: []string) -> map[string]string {
    out := make(map[string]string)
    for i in 0 ..< int(ts_node_child_count(root)) {
        decl := ts_node_child(root, u32(i))
        if string(ts_node_type(decl)) != "import_declaration" { continue }
        alias, path := "", ""
        for j in 0 ..< int(ts_node_child_count(decl)) {
            c := ts_node_child(decl, u32(j))
            switch string(ts_node_type(c)) {
            case "identifier": alias = _line_text(c, lines)
            case "string":
                for k in 0 ..< int(ts_node_child_count(c)) {
                    sc := ts_node_child(c, u32(k))
                    if string(ts_node_type(sc)) == "string_content" { path = _line_text(sc, lines) }
                }
            }
        }
        if path == "" { continue }
        if alias == "" {
            last := path
            if slash := strings.last_index_byte(last, '/'); slash >= 0 { last = last[slash+1:] }
            if colon := strings.last_index_byte(last, ':'); colon >= 0 { last = last[colon+1:] }
            alias = last
        }
        out[alias] = path
    }
    return out
}

// c201_extract_fn_name returns the package-qualified function name for calls whose
// result is discarded, e.g. "net.send" for a bare net.send(...) call.
// Using the qualified form prevents false-positives when user code defines its own
// proc with the same short name (e.g. a custom send :: proc(...)).
@(private="file")
c201_extract_fn_name :: proc(call_node: TSNode, file_lines: []string) -> string {
    child_count := ts_node_child_count(call_node)
    if child_count == 0 { return "" }

    fn_node := ts_node_child(call_node, 0)
    if ts_node_is_null(fn_node) { return "" }

    fn_type := string(ts_node_type(fn_node))
    switch fn_type {
    case "identifier":
        fn_name := naming_extract_text(fn_node, file_lines)
        // In tree-sitter-odin, pkg.fn(args) is sometimes parsed as:
        //   member_expression → call_expression → identifier
        // If our call_node's parent is a member_expression, extract the package
        // identifier from it and return "pkg.fn" to match the qualified stdlib list.
        parent := ts_node_parent(call_node)
        if !ts_node_is_null(parent) && string(ts_node_type(parent)) == "member_expression" {
            pc := ts_node_child_count(parent)
            for i in 0..<int(pc) {
                child := ts_node_child(parent, u32(i))
                if ts_node_is_null(child) { continue }
                if string(ts_node_type(child)) == "identifier" {
                    pkg := naming_extract_text(child, file_lines)
                    if len(pkg) > 0 && pkg != fn_name {
                        return fmt.tprintf("%s.%s", pkg, fn_name)
                    }
                }
            }
        }
        return fn_name
    case "member_expression":
        // Standard grammar: call_expression with member_expression as function child.
        // Extract pkg (first identifier) and fn (field_identifier or second identifier).
        n   := ts_node_child_count(fn_node)
        pkg := ""
        fn  := ""
        for i in 0..<int(n) {
            child := ts_node_child(fn_node, u32(i))
            if ts_node_is_null(child) { continue }
            ct   := string(ts_node_type(child))
            text := naming_extract_text(child, file_lines)
            if len(text) == 0 { continue }
            switch ct {
            case "identifier":
                if pkg == "" { pkg = text } else { fn = text }
            case "field_identifier":
                fn = text
            }
        }
        if len(pkg) > 0 && len(fn) > 0 { return fmt.tprintf("%s.%s", pkg, fn) }
        if len(fn)  > 0               { return fn }
        return pkg
    }
    return ""
}
