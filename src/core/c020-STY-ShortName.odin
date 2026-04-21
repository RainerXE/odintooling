package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C020: Short variable/parameter names  (opt-in)
// =============================================================================
//
// Flags local variables and procedure parameters whose names are shorter than
// a configurable minimum length, unless the name is on the allowed list.
//
// Rationale: single-letter and two-letter names make code harder to read and
// search. Loop indices (i, j, k) and coordinate variables (x, y, z) are
// idiomatic exceptions and belong on the allowed list.
//
// Configuration in odin-lint.toml:
//
//   [naming]
//   c020             = true        # enable rule (opt-in)
//   c020_min_length  = 3           # flag names shorter than this (default 3)
//   c020_allowed     = "i,j,k,x,y,z,n,ok,err,db,id"  # always-OK names
//
// Category: STYLE (opt-in, warn tier)
// =============================================================================

// C020Config bundles the rule's runtime settings, derived from OdinLintConfig.
C020Config :: struct {
    min_length: int,
    allowed:    map[string]bool,
}

// c020_build_config parses the comma-separated allowed string into a set.
// Caller owns the map and must call c020_free_config.
c020_build_config :: proc(cfg: OdinLintConfig) -> C020Config {
    result := C020Config{
        min_length = cfg.naming_c020_min_length if cfg.naming_c020_min_length > 0 else 3,
        allowed    = make(map[string]bool),
    }
    allowed_str := cfg.naming_c020_allowed
    if allowed_str == "" {
        allowed_str = "i,j,k,x,y,z,n,ok,err,db,id"
    }
    parts := strings.split(allowed_str, ",")
    defer delete(parts)
    for p in parts {
        trimmed := strings.trim(p, " \t")
        if len(trimmed) > 0 {
            result.allowed[trimmed] = true
        }
    }
    return result
}

c020_free_config :: proc(c: ^C020Config) {
    delete(c.allowed)
}

// c020_is_short returns true if name is shorter than min_length and not on
// the allowed list. Names starting with '_' are always exempt.
c020_is_short :: proc(name: string, c: C020Config) -> bool {
    if len(name) == 0 || name[0] == '_' { return false }
    if name in c.allowed { return false }
    return len(name) < c.min_length
}

// c020_scm_run processes @local_var and @param_name captures from naming_rules.scm.
c020_scm_run :: proc(
    file_path: string,
    result_captures: map[string]TSNode,
    file_lines: []string,
    c: C020Config,
) -> (Diagnostic, bool) {
    // Handle both local variable and parameter captures.
    name_node, is_local := result_captures["local_var"]
    if !is_local {
        name_node_p, is_param := result_captures["param_name"]
        if !is_param { return {}, false }
        name_node = name_node_p
    }

    name := naming_extract_text(name_node, file_lines)
    if len(name) == 0 { return {}, false }

    // For @local_var: only check declarations (:=), skip reassignments (=).
    if is_local {
        pt := ts_node_start_point(name_node)
        if int(pt.row) < len(file_lines) {
            line := file_lines[pt.row]
            end_col := int(ts_node_end_point(name_node).column)
            rest := line[min(end_col, len(line)):]
            rest = strings.trim_left(rest, " \t")
            if !strings.has_prefix(rest, ":=") { return {}, false }
        }
    }

    if !c020_is_short(name, c) { return {}, false }

    pt  := ts_node_start_point(name_node)
    ctx := "local variable"
    if !is_local { ctx = "parameter" }

    return Diagnostic{
        file    = file_path,
        line    = int(pt.row) + 1,
        column  = int(pt.column) + 1,
        rule_id = "C020",
        tier    = "style",
        message = fmt.aprintf(
            "Short %s name '%s' (length %d < %d) — use a descriptive name",
            ctx, name, len(name), c.min_length,
        ),
        has_fix   = false,
        diag_type = .VIOLATION,
    }, true
}
