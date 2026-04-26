// c017-STY-GlobalNaming.odin — C017: package-level variable naming convention.
// Package-scope variables should follow camelCase or _camelCase (opt-in);
// also shares the naming SCM pass to avoid redundant tree-sitter queries.
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C017: Package-level variable names must use camelCase  (opt-in)
// =============================================================================
//
// Package-level mutable variables declared with := must use camelCase:
//   - start with a lowercase letter
//   - no underscores (except a leading _ which marks private/unused)
//
// Violation:   severity_strings := [Severity]string{...}  ← snake_case
// Violation:   GlobalCounter    := 0                      ← PascalCase
// OK:          severityStrings  := [Severity]string{...}
// OK:          globalCounter    := 0
// OK:          _privateGlobal   := 0                      ← _ prefix exempt
//
// NOTE: This rule is opt-in (off by default). Standard Odin community
// convention uses snake_case for globals; enable only if your project
// prefers camelCase globals.
//
// Only covers := declarations (variable_declaration node).
// The var keyword form (var_declaration) is not yet covered.
//
// Category: STYLE (opt-in, warn tier)
// =============================================================================

// c017_is_camel_case returns true if name conforms to camelCase:
//   - starts with lowercase
//   - contains no underscores (after optional leading _)
c017_is_camel_case :: proc(name: string) -> bool {
    start := 0
    if len(name) > 0 && name[0] == '_' { start = 1 }
    if start >= len(name) { return true }
    if name[start] >= 'A' && name[start] <= 'Z' { return false }
    for i in start..<len(name) {
        if name[i] == '_' { return false }
    }
    return true
}

// c017_scm_run processes @pkg_var captures from naming_rules.scm.
c017_scm_run :: proc(
    file_path: string,
    result_captures: map[string]TSNode,
    file_lines: []string,
) -> (Diagnostic, bool) {
    pkg_node, ok := result_captures["pkg_var"]
    if !ok { return {}, false }

    name := naming_extract_text(pkg_node, file_lines)

    // Exempt: empty, single-char, _ prefix
    if len(name) <= 1 || name[0] == '_' { return {}, false }

    if c017_is_camel_case(name) { return {}, false }

    pt := ts_node_start_point(pkg_node)

    // Describe the specific violation
    msg: string
    if len(name) > 0 && name[0] >= 'A' && name[0] <= 'Z' {
        msg = fmt.aprintf(
            "Package-level variable '%s' starts with uppercase — use camelCase (e.g. '%c%s')",
            name, name[0] + 32, name[1:],
        )
    } else {
        msg = fmt.aprintf(
            "Package-level variable '%s' uses underscores — use camelCase instead of snake_case",
            name,
        )
    }

    return Diagnostic{
        file      = file_path,
        line      = int(pt.row) + 1,
        column    = int(pt.column) + 1,
        rule_id   = "C017",
        tier      = "style",
        message   = msg,
        has_fix   = true,
        fix       = fmt.aprintf("Rename '%s' to camelCase equivalent", name),
        diag_type = .VIOLATION,
    }, true
}
