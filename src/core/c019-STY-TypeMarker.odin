package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C019: Type Marker Suffixes (opt-in style rule)
// =============================================================================
//
// Enforces suffix conventions on variable names based on their declared type:
//
//   Type                     | Required suffix | Example
//   -------------------------+-----------------+------------------
//   pointer (^T, rawptr)     | _ptr            | player_ptr
//   slice ([]T)              | _slice          | players_slice
//   dynamic array ([dynamic])| _dyn            | players_dyn
//   fixed array ([N]T)       | _arr            | players_arr
//   map (map[K]V)            | _map            | scores_map
//   allocator (*.Allocator)  | _alloc          | arena_alloc
//   cstring                  | _cstr           | label_cstr
//   proc type (proc(...))    | _fn             | callback_fn
//   multi-pointer ([^]T)     | _buf            | data_buf
//   value types              | (none)          | player, count
//
// SCOPE: local variables and function parameters. Struct fields are excluded.
//
// DETECTION:
//   Phase 1 (this implementation, no OLS needed):
//     - Explicit type annotations: name: ^T, name: []T, etc. → 100% accurate
//     - Inferred := with recognisable RHS: &expr, new(T), make([]T,...) → high-confidence
//   Phase 2 (requires OLS type resolution):
//     - Inferred := where RHS is an opaque proc call (e.g. get_player())
//     - Maybe(T) types
//
// ENABLING:
//   Add to odin-lint.toml:
//     [naming]
//     c019 = true
//
// SUPPRESSION:
//   player: ^Player  // odin-lint:ignore C019
//
// =============================================================================

// C019TypeKind categorises a variable's type for suffix convention checking.
C019TypeKind :: enum {
    Unknown,
    Value,        // primitive / struct / enum — no suffix needed
    Pointer,      // ^T or rawptr → _ptr
    Slice,        // []T → _slice
    DynArray,     // [dynamic]T → _dyn
    FixedArray,   // [N]T → _arr
    Map,          // map[K]V → _map
    Allocator,    // *.Allocator → _alloc
    CString,      // cstring → _cstr
    ProcType,     // proc(...) → _fn
    MultiPointer, // [^]T → _buf
}

c019_required_suffix :: proc(kind: C019TypeKind) -> string {
    switch kind {
    case .Pointer:      return "_ptr"
    case .Slice:        return "_slice"
    case .DynArray:     return "_dyn"
    case .FixedArray:   return "_arr"
    case .Map:          return "_map"
    case .Allocator:    return "_alloc"
    case .CString:      return "_cstr"
    case .ProcType:     return "_fn"
    case .MultiPointer: return "_buf"
    case .Value, .Unknown:
    }
    return ""
}

c019_kind_label :: proc(kind: C019TypeKind) -> string {
    switch kind {
    case .Pointer:      return "pointer (^T)"
    case .Slice:        return "slice ([]T)"
    case .DynArray:     return "dynamic array ([dynamic]T)"
    case .FixedArray:   return "fixed array ([N]T)"
    case .Map:          return "map (map[K]V)"
    case .Allocator:    return "allocator"
    case .CString:      return "cstring"
    case .ProcType:     return "proc type"
    case .MultiPointer: return "multi-pointer ([^]T)"
    case .Value, .Unknown:
    }
    return "value"
}

// ---------------------------------------------------------------------------
// Rule entry point
// ---------------------------------------------------------------------------

C019Rule :: proc() -> Rule {
    return Rule{
        id       = "C019",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,
        message  = c019_message,
        fix_hint = c019_fix_hint,
    }
}

c019_message  :: proc() -> string { return "variable name does not match its type marker convention" }
c019_fix_hint :: proc() -> string { return "Append the required suffix (e.g. _ptr, _slice, _map, _alloc)" }

// c019_scm_run processes the type_marker.scm query results and emits diagnostics.
// db is optional (nil = Phase 1 only). When provided, Phase 2 graph lookup is
// attempted for inferred := assignments whose type cannot be determined from syntax.
c019_scm_run :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
    db:         ^GraphDB = nil,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    // Deduplicate by (line, col) — the same identifier can be captured
    // by multiple patterns (e.g. var_decl + local_assign patterns both fire).
    seen := make(map[string]bool)
    defer delete(seen)

    suppressions := collect_suppressions(1, len(file_lines), file_lines)
    defer delete(suppressions)
    diags        := make([dynamic]Diagnostic)

    for result in results {
        id_node, name, kind := c019_extract_and_classify(result, file_lines, db) or_continue
        if kind == .Value || kind == .Unknown { continue }

        pt   := ts_node_start_point(id_node)
        lnum := int(pt.row) + 1   // 1-based
        col  := int(pt.column) + 1

        key := fmt.tprintf("%d:%d", lnum, col)
        if seen[key] { continue }
        seen[key] = true

        required := c019_required_suffix(kind)
        if required == "" { continue }
        if strings.has_suffix(name, required) { continue }

        if is_suppressed("C019", lnum, suppressions) { continue }

        append(&diags, Diagnostic{
            file      = file_path,
            line      = lnum,
            column    = col,
            rule_id   = "C019",
            tier      = "style",
            message   = fmt.aprintf(
                "'%s' is a %s — name should end in '%s'",
                name, c019_kind_label(kind), required,
            ),
            has_fix   = true,
            fix       = fmt.aprintf("Rename to '%s%s'", name, required),
            diag_type = .VIOLATION,
        })
    }

    return diags[:]
}

// ---------------------------------------------------------------------------
// Classification helpers
// ---------------------------------------------------------------------------

// c019_extract_and_classify takes a query result, determines whether the
// captured identifier is a variable NAME (not a type identifier), and
// returns the identifier node, its text, and its classified type kind.
// db is optional — when non-nil, Phase 2 graph lookup is attempted for
// inferred := assignments whose type cannot be determined from syntax alone.
@(private)
c019_extract_and_classify :: proc(
    result:     QueryResult,
    file_lines: []string,
    db:         ^GraphDB = nil,
) -> (id_node: TSNode, name: string, kind: C019TypeKind, ok: bool) {
    var_node,   is_var   := result.captures["c019_var"]
    param_node, is_param := result.captures["c019_param"]
    local_node, is_local := result.captures["c019_local"]

    if !is_var && !is_param && !is_local { return {}, "", .Unknown, false }

    active := var_node
    if is_param { active = param_node }
    if is_local { active = local_node }

    pt   := ts_node_start_point(active)
    row  := int(pt.row)
    col  := int(pt.column)

    if row >= len(file_lines) { return {}, "", .Unknown, false }
    raw_line := file_lines[row]

    // Strip inline comment from the line before analysis
    line := raw_line
    if ci := strings.index(raw_line, "//"); ci >= 0 {
        line = raw_line[:ci]
    }

    ident := naming_extract_text(active, file_lines)
    if len(ident) == 0 || ident == "_" { return {}, "", .Unknown, false }

    if is_var || is_param {
        // Explicit type annotation path.
        // The variable NAME must appear before the ':' type separator.
        colon := c019_find_type_colon(line)
        if colon < 0 || col >= colon { return {}, "", .Unknown, false }

        type_text := c019_extract_explicit_type(line, colon)
        return active, ident, c019_classify_explicit(type_text), true
    }

    // Inferred := path.
    // Variable name must be on the LHS (before ':=').
    assign_pos := strings.index(line, ":=")
    if assign_pos < 0 || col >= assign_pos { return {}, "", .Unknown, false }

    // Skip if there is a comma between col and ':=' — multi-return; can't
    // map positions to types without OLS.
    lhs := line[col:assign_pos]
    if strings.contains(lhs, ",") { return {}, "", .Unknown, false }

    rhs        := strings.trim(line[assign_pos+2:], " \t")
    inferred   := c019_classify_inferred(rhs)

    // Phase 2: if Phase 1 couldn't determine the type and we have a graph DB,
    // try to look up the called proc's return type.
    if inferred == .Unknown && db != nil {
        inferred = c019_classify_from_graph(db, rhs)
    }

    return active, ident, inferred, true
}

// c019_find_type_colon returns the index of the ':' used as a type separator,
// skipping ':=' (inferred decl) and '::' (constant decl).
// Must check both prev and next to correctly skip BOTH colons of '::'.
@(private)
c019_find_type_colon :: proc(line: string) -> int {
    for i in 0..<len(line) {
        if line[i] != ':' { continue }
        prev := line[i-1] if i > 0 else 0
        next := line[i+1] if i+1 < len(line) else 0
        if next == '=' || next == ':' { continue }  // skip :=  and first colon of ::
        if prev == ':' { continue }                  // skip second colon of ::
        return i
    }
    return -1
}

// c019_extract_explicit_type extracts the type text from a line after the
// type-separator colon (index colon_pos). Stops at the value '=' or EOL.
@(private)
c019_extract_explicit_type :: proc(line: string, colon_pos: int) -> string {
    if colon_pos + 1 >= len(line) { return "" }
    rest := line[colon_pos+1:]

    // Stop at value '=' (but not ':=' or '==')
    for i in 0..<len(line[colon_pos+1:]) {
        c := rest[i]
        if c == '=' {
            // Check it's not == or :=
            prev := rest[i-1] if i > 0 else 0
            next := rest[i+1] if i+1 < len(rest) else 0
            if prev != ':' && prev != '!' && prev != '<' && prev != '>' && next != '=' {
                rest = rest[:i]
                break
            }
        }
    }
    return strings.trim(rest, " \t")
}

// c019_classify_explicit maps an explicit type annotation text to a C019TypeKind.
@(private)
c019_classify_explicit :: proc(type_text: string) -> C019TypeKind {
    t := strings.trim_left(type_text, " \t")
    if len(t) == 0 { return .Unknown }

    // Order matters: check most specific prefixes first.
    if strings.has_prefix(t, "[]")       { return .Slice }
    if strings.has_prefix(t, "[dynamic]") { return .DynArray }
    if strings.has_prefix(t, "[^]")       { return .MultiPointer }
    if strings.has_prefix(t, "^")         { return .Pointer }
    if strings.has_prefix(t, "map[")      { return .Map }
    if strings.has_prefix(t, "proc")      { return .ProcType }

    // [N]T — fixed array (bracket that isn't [] / [dynamic] / [^])
    if strings.has_prefix(t, "[") { return .FixedArray }

    // Named types
    if t == "rawptr" { return .Pointer }
    if t == "cstring" { return .CString }

    // Allocator: any type whose last component is "Allocator"
    // Handles mem.Allocator, runtime.Allocator, custom allocators
    bare := t
    if dot := strings.last_index(t, "."); dot >= 0 {
        bare = t[dot+1:]
    }
    if bare == "Allocator" { return .Allocator }

    return .Value
}

// c019_classify_inferred maps an inferred ':=' RHS expression to a kind.
// Returns .Unknown when the type cannot be determined without OLS.
@(private)
c019_classify_inferred :: proc(rhs: string) -> C019TypeKind {
    r := strings.trim_left(rhs, " \t")
    if len(r) == 0 { return .Unknown }

    // & address-of → pointer
    if strings.has_prefix(r, "&") { return .Pointer }

    // new(T) → pointer
    if strings.has_prefix(r, "new(") { return .Pointer }

    // make(...) calls — inspect the type argument
    if strings.has_prefix(r, "make(") {
        inner := r[5:]  // skip "make("
        inner  = strings.trim_left(inner, " \t")
        if strings.has_prefix(inner, "[]")        { return .Slice }
        if strings.has_prefix(inner, "[dynamic]") { return .DynArray }
        if strings.has_prefix(inner, "map[")      { return .Map }
        return .Unknown  // make([N]T) is unusual; skip
    }

    // cstring cast / conversion
    if strings.has_prefix(r, "cstring(") { return .CString }

    return .Unknown  // proc calls, field access, etc. — need graph or OLS
}

// =============================================================================
// Phase 2 — graph-backed return type resolution
// =============================================================================

// c019_classify_from_graph looks up the proc being called in the graph DB
// and classifies the type from its stored return_type.
// Returns .Unknown when the proc is not in the graph or type is ambiguous.
@(private)
c019_classify_from_graph :: proc(db: ^GraphDB, rhs: string) -> C019TypeKind {
    if db == nil { return .Unknown }
    proc_name := c019_call_proc_name(rhs)
    if proc_name == "" { return .Unknown }

    node, found := graph_get_node(db, proc_name)
    if !found { return .Unknown }
    defer graph_free_node_info(node)

    rt := node.return_type
    if rt == "" { return .Unknown }

    type_text := c019_unwrap_return_type(rt)
    if type_text == "" { return .Unknown }

    kind := c019_classify_explicit(type_text)
    if kind == .Value { return .Unknown } // value return → no suffix needed; skip
    return kind
}

// c019_call_proc_name extracts the bare proc name from an RHS call expression.
// "get_player()"    → "get_player"
// "os.open(path)"   → "open"
// "1 + 2"           → ""  (not a call)
@(private)
c019_call_proc_name :: proc(rhs: string) -> string {
    paren := strings.index(rhs, "(")
    if paren < 0 { return "" }
    fn_expr := strings.trim_space(rhs[:paren])
    if len(fn_expr) == 0 { return "" }
    // Reject if fn_expr contains spaces or operators — it's not a plain call
    for ch in fn_expr {
        if ch == ' ' || ch == '+' || ch == '-' || ch == '*' || ch == '!' { return "" }
    }
    if dot := strings.last_index(fn_expr, "."); dot >= 0 {
        return fn_expr[dot+1:]
    }
    return fn_expr
}

// c019_unwrap_return_type extracts the first (primary) type from a return
// type string as produced by _extract_return_type in dna_exporter.odin.
//
// Examples:
//   "^Player"              → "^Player"
//   "(result: ^Player)"    → "^Player"
//   "(^Player, bool)"      → "^Player"  (first item; caller already skipped multi-assign)
//   "(ok: bool)"           → ""         (bool return → .Value; skip)
@(private)
c019_unwrap_return_type :: proc(rt: string) -> string {
    s := strings.trim_space(rt)

    // Strip outer parens
    if len(s) >= 2 && s[0] == '(' && s[len(s)-1] == ')' {
        s = strings.trim_space(s[1:len(s)-1])
    }

    // Take first item before comma
    if comma := strings.index(s, ","); comma >= 0 {
        s = strings.trim_space(s[:comma])
    }

    // Strip named return: "name: ^Type" → "^Type"
    if colon := strings.index(s, ":"); colon >= 0 {
        after := colon + 1
        if after < len(s) && s[after] != ':' && s[after] != '=' {
            s = strings.trim_space(s[after:])
        }
    }

    return s
}
