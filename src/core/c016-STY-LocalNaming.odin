package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C016: Local variable names must use snake_case
// =============================================================================
//
// Inside proc bodies, all newly declared variables (:= declarations) must use
// snake_case — all lowercase letters, digits, and underscores only.
//
// Violation:   playerCount := 0        ← camelCase
// Violation:   PlayerPtr   := &p       ← PascalCase
// OK:          player_count := 0
// OK:          player_ptr   := &p
// OK:          i := 0                  ← single-char loop var (exempt)
// OK:          _unused := foo()        ← _ prefix (exempt)
//
// Category: STYLE (opt-in, warn tier)
// =============================================================================

// c016_is_snake_case returns true if every character in name is lowercase,
// a digit, or an underscore.
c016_is_snake_case :: proc(name: string) -> bool {
    for ch in name {
        if ch >= 'A' && ch <= 'Z' { return false }
    }
    return true
}

// c016_scm_run processes @local_var captures from naming_rules.scm.
// Called from naming_scm_run — results are merged into the same diagnostic slice.
c016_scm_run :: proc(
    file_path:  string,
    result_captures: map[string]TSNode,
    file_lines: []string,
) -> (Diagnostic, bool) {
    local_node, ok := result_captures["local_var"]
    if !ok { return {}, false }

    name := naming_extract_text(local_node, file_lines)

    // Exempt: empty, single-char (loop vars i/j/k/x/y/n etc.), _ prefix
    if len(name) <= 1 || name[0] == '_' { return {}, false }

    // Only flag := declarations, not = reassignments.
    // Check by looking for := anywhere on the same source line.
    pt := ts_node_start_point(local_node)
    row := int(pt.row)
    if row < 0 || row >= len(file_lines) { return {}, false }
    line := file_lines[row]
    if !strings.contains(line, ":=") { return {}, false }

    if c016_is_snake_case(name) { return {}, false }

    return Diagnostic{
        file      = file_path,
        line      = row + 1,
        column    = int(pt.column) + 1,
        rule_id   = "C016",
        tier      = "style",
        message   = fmt.aprintf(
            "Local variable '%s' is not snake_case — use lowercase_with_underscores",
            name,
        ),
        has_fix   = true,
        fix       = fmt.aprintf("Rename '%s' to snake_case equivalent", name),
        diag_type = .VIOLATION,
    }, true
}
