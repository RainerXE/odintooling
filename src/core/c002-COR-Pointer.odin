package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C002: Double-free detection (SCM query engine implementation)
// =============================================================================
//
// Detects when the same allocation is freed more than once via defer:
//
//   buf := make([]u8, 1024)
//   defer free(buf)        // first free — ok
//   defer free(buf)        // second free — C002 VIOLATION
//
// Handles both plain calls (defer free(x)) and qualified calls (defer mem.free(x)).
// Scope-aware: detects doubles within the same procedure; cross-procedure
// occurrences of the same variable name are not flagged.
//
// =============================================================================

// ---------------------------------------------------------------------------
// Rule entry point
// ---------------------------------------------------------------------------

// C002Rule returns the Rule struct for the registry.
// Detection is performed by c002_scm_matcher (called directly from main.odin
// because it needs TSNode / CompiledQuery parameters beyond Rule.matcher).
C002Rule :: proc() -> Rule {
    return Rule{
        id       = "C002",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,
        message  = c002_message,
        fix_hint = c002_fix_hint,
    }
}

c002_message :: proc() -> string {
    return "Double-free: same variable freed more than once via defer in this scope"
}

c002_fix_hint :: proc() -> string {
    return "Remove the duplicate defer free — each allocation should be freed exactly once"
}

// ---------------------------------------------------------------------------
// SCM-based detection
// ---------------------------------------------------------------------------

// Position tracks a source location for a freed variable.
Position :: struct {
    line: int,
    col:  int,
}

// c002_scm_block_scope returns the start_byte of the innermost enclosing
// `block` node for a given node.  Using block-level scope means two defer frees
// of the same name in different `if` branches (different blocks) are not flagged,
// while two defer frees in the same block ARE flagged.  Returns 0 if no block found.
c002_scm_block_scope :: proc(node: TSNode) -> u32 {
    current := ts_node_parent(node)
    for !ts_node_is_null(current) {
        type_str := string(ts_node_type(current))
        if type_str == "block" {
            return ts_node_start_byte(current)
        }
        current = ts_node_parent(current)
    }
    return 0
}

// c002_scm_matcher detects double-free patterns using the memory_safety.scm query.
//
//   1. Run the defer_free query → captures @freed_var for each defer free(x)
//   2. Group by (enclosing_proc_start_byte, var_name) to avoid cross-procedure FPs
//   3. Any group with ≥ 2 entries emits a violation for the second+ occurrences
c002_scm_matcher :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    // Key: "proc_start_byte:var_name" → ordered list of positions
    free_sites := make(map[string][dynamic]Position)
    defer {
        for _, &sites in free_sites { delete(sites) }
        delete(free_sites)
    }

    for result in results {
        freed_node, ok := result.captures["freed_var"]
        if !ok { continue }

        name := c002_extract_ident_text_from_tsnode(freed_node, file_lines)
        if name == "" || name == "_" { continue }

        scope_byte := c002_scm_block_scope(freed_node)
        key        := fmt.tprintf("%d:%s", scope_byte, name)

        pt  := ts_node_start_point(freed_node)
        pos := Position{line = int(pt.row) + 1, col = int(pt.column) + 1}
        // Map values are not addressable — use read-modify-write.
        existing, _ := free_sites[key]
        append(&existing, pos)
        free_sites[key] = existing
    }

    diagnostics := make([dynamic]Diagnostic)

    for key, sites in free_sites {
        if len(sites) < 2 { continue }

        colon    := strings.index_byte(key, ':')
        var_name := key[colon+1:] if colon >= 0 else key

        // First defer free is fine; second+ are violations.
        for i in 1..<len(sites) {
            site := sites[i]
            append(&diagnostics, Diagnostic{
                file      = file_path,
                line      = site.line,
                column    = site.col,
                rule_id   = "C002",
                tier      = "correctness",
                message   = fmt.aprintf(
                    "Double-free: '%s' is already freed by a defer in this scope",
                    var_name,
                ),
                has_fix   = true,
                fix       = fmt.aprintf("Remove the duplicate 'defer free(%s)'", var_name),
                diag_type = .VIOLATION,
            })
        }
    }

    return diagnostics[:]
}

// c002_extract_ident_text_from_tsnode extracts identifier text from a TSNode
// using file_lines for reliable byte-offset-free extraction.
c002_extract_ident_text_from_tsnode :: proc(node: TSNode, lines: []string) -> string {
    type_str := string(ts_node_type(node))
    if type_str != "identifier" { return "" }

    pt      := ts_node_start_point(node)
    line_idx := int(pt.row)
    if line_idx < 0 || line_idx >= len(lines) { return "" }

    line := lines[line_idx]
    col  := int(pt.column)
    if col < 0 || col >= len(line) { return "" }

    rest := line[col:]
    end  := 0
    for end < len(rest) {
        c := rest[end]
        if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') {
            end += 1
        } else {
            break
        }
    }
    return rest[:end]
}
