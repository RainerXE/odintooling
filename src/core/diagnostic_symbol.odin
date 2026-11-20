// diagnostic_symbol.odin — attach the enclosing procedure name to collected diagnostics.
//
// The lint channel wants a stable `symbol` per finding (the procedure/function to
// repair), but individual matchers only know a source line. This pass runs once per
// file after all rules have contributed, walks the tree-sitter AST, and fills the
// field only for diagnostics that do not already carry one.

package core

import "core:os"
import "core:strings"

// annotate_file_symbols reads and parses file_path, then fills diags' symbols.
// It is called only when at least one diagnostic was collected, so clean files
// pay no extra parse.
annotate_file_symbols :: proc(
    file_path: string,
    diags:     []Diagnostic,
    ts_parser: ^TreeSitterASTParser,
) {
    if len(diags) == 0 { return }

    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil { return }
    defer delete(content)

    source := string(content)
    tree, ok := parseSource(ts_parser.adapter.parser, ts_parser.adapter.language, source)
    if !ok { return }
    defer ts_tree_delete(tree)

    root := getRootNode(tree)
    if ts_node_is_null(root) { return }
    annotate_diagnostic_symbols(diags, root, source)
}

// annotate_diagnostic_symbols fills symbols from an already-parsed tree.
// Used by analyze_content, which keeps its parse alive for the whole call.
annotate_diagnostic_symbols :: proc(diags: []Diagnostic, root: TSNode, source: string) {
    for i in 0 ..< len(diags) {
        d := &diags[i]
        if d.symbol != "" || d.line <= 0 { continue }
        if name := _enclosing_proc_name(root, source, d.line - 1); name != "" {
            d.symbol = strings.clone(name)
        }
    }
}

// _enclosing_proc_name walks the one child that contains row at each level and
// remembers the innermost named procedure_declaration on that path.
@(private="file")
_enclosing_proc_name :: proc(root: TSNode, source: string, row: int) -> string {
    name := ""
    cur := root
    for !ts_node_is_null(cur) {
        if string(ts_node_type(cur)) == "procedure_declaration" {
            if n := _procedure_decl_name(cur, source); n != "" { name = n }
        }

        next: TSNode
        for i in 0 ..< int(ts_node_child_count(cur)) {
            child := ts_node_child(cur, u32(i))
            if row >= int(ts_node_start_point(child).row) && row <= int(ts_node_end_point(child).row) {
                next = child
                break
            }
        }
        if ts_node_is_null(next) { break }
        cur = next
    }
    return name
}

// _procedure_decl_name returns the first identifier of a procedure declaration.
// Overloaded groups contain per-member procedure_declaration nodes, so this
// reports the member being repaired rather than the group name.
@(private="file")
_procedure_decl_name :: proc(decl: TSNode, source: string) -> string {
    for i in 0 ..< int(ts_node_child_count(decl)) {
        child := ts_node_child(decl, u32(i))
        if string(ts_node_type(child)) == "identifier" {
            return source[ts_node_start_byte(child):ts_node_end_byte(child)]
        }
    }
    return ""
}
