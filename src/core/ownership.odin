// ownership.odin — who owns the memory a procedure allocates?
//
// For every allocation inside a procedure (make, new, new_clone and the stdlib calls that
// allocate) this records two facts that decide whether a free is owed:
//
//   allocator_kind  which allocator the memory comes from
//       default  context.allocator (or none given): the caller of make/new must free it
//       param    an `allocator: mem.Allocator` parameter of this procedure: the caller of
//                THIS procedure chose it, and owns the result
//       temp     context.temp_allocator: released wholesale, never freed one by one
//       custom   any other allocator (an arena, a reassigned context.allocator): released
//                with its allocator
//
//   disposition     what became of the memory (strongest wins, in this order)
//       freed_deferred   `defer delete(x)` / `defer free(x)` / `defer thing_destroy(&x)`
//       freed            a delete/free/destroy call on it later in the procedure
//       returned         handed to the caller: this procedure is a factory
//       stored           put somewhere that outlives the call (a field, a global, append(&list, x))
//       passed           given to another procedure: ownership unknown from here
//       unfreed          none of the above
//
// Most Odin code allocates from temp or an arena on purpose, so "never freed" is only a
// finding when the allocator is default or param. That is why the allocator is recorded.
//
// This is a syntactic, per-procedure analysis: it follows the NAME the result is bound to
// through the procedure body. It does not follow aliases or cross procedure boundaries.
package core

import "core:fmt"
import "core:strings"

AllocSite :: struct {
    api:            string,   // make | new | new_clone | mem.alloc | strings.clone | ...
    elem_type:      string,   // the type allocated, as written ("Foo", "pkg.Foo"); "" if unknown
    allocator_kind: string,   // default | temp | param | custom
    allocator_expr: string,   // the allocator argument as written; "" when none was given
    var_name:       string,   // the local the result was bound to; "" if none
    disposition:    string,   // freed_deferred | freed | returned | stored | passed | unfreed
    line, col:      int,
    via:            i64,      // for a site found through a call: the handle of the procedure called (0 otherwise)
}

ProcOwnership :: struct {
    sites:      [dynamic]AllocSite,
    free_calls: int,         // calls to a free-like procedure (delete, free, *_destroy, ...)
    sinks:      [dynamic]int, // parameters (0-based) this procedure frees: it takes ownership of them
    effects:    [dynamic]ParamEffect, // the parameters it keeps (stores or returns) or only reads
    defaults:   [dynamic]ParamDefault, // its allocator parameters and what each defaults to
}

// ParamEffect is what a procedure does with one of its parameters, besides freeing it (that is a sink).
ParamEffect :: struct {
    idx:    int,
    effect: string,   // kept: stored or returned, so the caller no longer owns it | read: only looked at, the caller still does
}

ParamDefault :: struct {
    name: string,
    kind: string,   // default | temp | custom | none
}

// CrossCall is what is known about the procedure a call resolves to. It lets a caller see
// through the call: a factory's result is an allocation owned by the caller, and a sink frees
// the argument it is given.
CrossCall :: struct {
    name:         string,
    callee:       i64,      // the handle of the procedure the call resolves to
    factory:      bool,
    factory_kind: string,   // default | param: whose allocator the factory's result comes from
    elem_type:    string,   // the type the factory allocates, as written in its own package
    default_kind: string,   // what the allocator parameter falls back to when the caller passes none
    sink_mask:    u64,      // bit i set: the callee frees its i-th argument
    keep_mask:    u64,      // bit i set: the callee stores or returns its i-th argument (the caller no longer owns it)
    read_mask:    u64,      // bit i set: the callee only reads its i-th argument (the caller still owns it)
}

// CrossInfo maps the position of a call's callee name (line, column) to what it resolves to.
CrossInfo :: struct {
    calls: map[[2]int]CrossCall,
}

// Everything below allocates from the temp allocator: results are consumed immediately by
// graph_record_ownership, so nothing here needs freeing.

@(private="file")
_ntype :: proc(n: TSNode) -> string { return string(ts_node_type(n)) }

@(private="file")
_same :: proc(a, b: TSNode) -> bool {
    return ts_node_start_byte(a) == ts_node_start_byte(b) && ts_node_end_byte(a) == ts_node_end_byte(b)
}

// _named returns a node's named children (skips punctuation tokens such as "(" "," "=").
@(private="file")
_named :: proc(n: TSNode) -> []TSNode {
    out := make([dynamic]TSNode, context.temp_allocator)
    for i in 0 ..< int(ts_node_child_count(n)) {
        c := ts_node_child(n, u32(i))
        if bool(ts_node_is_named(c)) { append(&out, c) }
    }
    return out[:]
}

// _text is the source text of a node, across lines if need be, capped at 200 bytes.
@(private="file")
_text :: proc(n: TSNode, lines: []string) -> string {
    sp := ts_node_start_point(n)
    ep := ts_node_end_point(n)
    r0, c0, r1, c1 := int(sp.row), int(sp.column), int(ep.row), int(ep.column)
    if r0 < 0 || r0 >= len(lines) { return "" }
    if r0 == r1 {
        line := lines[r0]
        if c1 > len(line) { c1 = len(line) }
        if c0 > c1 { return "" }
        return line[c0:c1]
    }
    sb := strings.builder_make(context.temp_allocator)
    for r in r0 ..= min(r1, len(lines) - 1) {
        line := lines[r]
        from, to := 0, len(line)
        if r == r0 { from = min(c0, len(line)) }
        if r == r1 { to = min(c1, len(line)) }
        if from > to { continue }
        if r > r0 { strings.write_byte(&sb, ' ') }
        strings.write_string(&sb, strings.trim_space(line[from:to]))
        if strings.builder_len(sb) > 200 { break }
    }
    return strings.to_string(sb)
}

// =============================================================================
// What counts as an allocation, and as a free
// =============================================================================

// _alloc_api names the allocating procedures. A bare make/new/new_clone is the builtin; a
// qualified name is matched on the qualifier as written (mem, strings, fmt, os, slice).
@(private="file")
_alloc_api :: proc(qual, name: string) -> (api: string, ok: bool) {
    if qual == "" {
        switch name {
        case "make", "new", "new_clone": return name, true
        }
        return "", false
    }
    hit := false
    switch qual {
    case "mem":
        switch name {
        case "alloc", "alloc_bytes", "alloc_bytes_non_zeroed", "new", "new_clone": hit = true
        }
    case "strings":
        switch name {
        case "clone", "clone_to_cstring", "clone_from_cstring", "concatenate", "join", "split", "to_lower", "to_upper": hit = true
        }
    case "fmt":
        switch name {
        case "aprintf", "aprint", "aprintln", "aprintfln": hit = true
        }
    case "os":
        switch name {
        case "read_entire_file", "read_entire_file_from_path": hit = true
        }
    case "slice":
        switch name {
        case "clone", "clone_to_dynamic": hit = true
        }
    }
    if !hit { return "", false }
    return fmt.tprintf("%s.%s", qual, name), true
}

// _is_free_name says whether a procedure name releases memory. It matches whole words of a
// snake_case name, so `write_escaped_newlines` is not an allocator and `delete_cookie` is
// a free but `delete_key` (a map entry, not memory) is not.
@(private="file")
_is_free_name :: proc(name: string) -> bool {
    switch name {
    case "delete", "free", "free_all": return true
    case "delete_key", "delete_elem", "delete_at": return false
    }
    for tok in strings.split(name, "_", context.temp_allocator) {
        switch tok {
        case "free", "delete", "destroy", "release": return true
        }
    }
    return false
}

// _stores_arg names the container procedures that keep an argument alive past the call.
@(private="file")
_stores_arg :: proc(name: string) -> bool {
    switch name {
    case "append", "append_elem", "append_elems", "inject_at", "assign_at", "push", "push_back", "push_front":
        return true
    }
    return false
}

// _reads_only names the procedures that look at a value without keeping or releasing it.
@(private="file")
_reads_only :: proc(qual, name: string) -> bool {
    // fmt.println and friends look at their arguments; fmt.set_user_formatters keeps one
    if qual == "fmt" { return strings.contains(name, "print") }
    if qual == "log" { return true }
    switch name {
    case "len", "cap", "assert", "ensure", "panic", "print", "println", "printf", "printfln",
         "eprint", "eprintln", "eprintf", "eprintfln", "size_of", "type_of":
        return true
    }
    return false
}

// _transparent names the conversions that pass a value through as an alias of itself: the result
// of raw_data(x) or wstring(raw_data(x)) is x's memory under another type, so what happens to the
// result happens to x.
@(private="file")
_transparent :: proc(qual, name: string) -> bool {
    if qual != "" { return false }
    switch name {
    case "raw_data", "cstring", "cstring16", "wstring", "string", "rawptr": return true
    }
    return false
}

// _has_named_args: a call with `name = value` arguments no longer lines up with the parameter list by position.
@(private="file")
_has_named_args :: proc(call: TSNode) -> bool {
    for i in 0 ..< int(ts_node_child_count(call)) {
        if _ntype(ts_node_child(call, u32(i))) == "=" { return true }
    }
    return false
}

// _is_decl_assign says whether an assignment declares its left-hand names (`:=`) rather
// than assigning to names declared elsewhere (`=`).
@(private="file")
_is_decl_assign :: proc(lhs, rhs: []TSNode, lines: []string) -> bool {
    if len(lhs) == 0 || len(rhs) == 0 { return false }
    sp := ts_node_end_point(lhs[len(lhs) - 1])
    row := int(sp.row)
    if row < 0 || row >= len(lines) { return false }
    line := lines[row]
    from := min(int(sp.column), len(line))
    to := len(line)
    if rp := ts_node_start_point(rhs[0]); int(rp.row) == row { to = min(int(rp.column), len(line)) }
    if from > to { return false }
    return strings.contains(line[from:to], ":=")
}

// _assign_split divides the flat children of an assignment_statement into its left-hand
// and right-hand expressions. `a, b := x, y` has two of each; `data, ok := f()` has two on
// the left and one call on the right.
@(private="file")
_assign_split :: proc(kids: []TSNode) -> (lhs, rhs: []TSNode) {
    n := len(kids)
    if n < 2 { return }
    if n % 2 == 0 { return kids[:n / 2], kids[n / 2:] }
    return kids[:n - 1], kids[n - 1:]
}

// =============================================================================
// Reading a procedure
// =============================================================================

@(private="file")
Collected :: struct {
    calls:   [dynamic]TSNode,
    idents:  [dynamic]TSNode,
    assigns: [dynamic]TSNode,
    decls:   [dynamic]TSNode,   // var_declaration:  buf: Buffer = {...}
}

// _collect gathers the calls, identifiers and assignments of a procedure body. It does not
// enter nested NAMED procedures (they are analysed as procedures of their own), but it does
// enter anonymous procedure literals, as call attribution does.
@(private="file")
_collect :: proc(n: TSNode, out: ^Collected) {
    switch _ntype(n) {
    case "procedure_declaration": return
    case "call_expression":       append(&out.calls, n)
    case "identifier":            append(&out.idents, n)
    case "assignment_statement":  append(&out.assigns, n)
    case "var_declaration":       append(&out.decls, n)
    }
    for i in 0 ..< int(ts_node_child_count(n)) {
        _collect(ts_node_child(n, u32(i)), out)
    }
}

// _proc_parts finds the body block and the parameter list of a procedure_declaration.
@(private="file")
_proc_parts :: proc(decl: TSNode) -> (body, params: TSNode) {
    for k in _named(decl) {
        if _ntype(k) != "procedure" { continue }
        for p in _named(k) {
            switch _ntype(p) {
            case "block":      body = p
            case "parameters": params = p
            }
        }
    }
    return
}

// _param_allocators returns the names of parameters whose type mentions Allocator.
@(private="file")
_param_allocators :: proc(params: TSNode, lines: []string) -> map[string]bool {
    out := make(map[string]bool, context.temp_allocator)
    if ts_node_is_null(params) { return out }
    for par in _named(params) {
        kind := _ntype(par)
        if kind != "parameter" && kind != "default_parameter" { continue }
        names := make([dynamic]string, context.temp_allocator)
        is_alloc := false
        for k in _named(par) {
            switch _ntype(k) {
            case "identifier":
                append(&names, _text(k, lines))
            case "type":
                t := _text(k, lines)
                is_alloc = strings.contains(t, "Allocator") || strings.contains(t, "Arena")
            case:
                // the default value: `allocator := context.allocator`
                if kind == "default_parameter" && strings.contains(_text(k, lines), "allocator") { is_alloc = true }
            }
        }
        if is_alloc { for n in names { out[n] = true } }
    }
    return out
}

// _param_default_kinds records, for each allocator parameter, what it defaults to.
@(private="file")
_param_default_kinds :: proc(params: TSNode, lines: []string, param_allocs: map[string]bool, out: ^[dynamic]ParamDefault) {
    if ts_node_is_null(params) { return }
    for par in _named(params) {
        kind := _ntype(par)
        if kind != "parameter" && kind != "default_parameter" { continue }
        names := make([dynamic]string, context.temp_allocator)
        value := ""
        for k in _named(par) {
            switch _ntype(k) {
            case "identifier": append(&names, _text(k, lines))
            case "type":
            case:              value = _text(k, lines)
            }
        }
        for n in names {
            if !param_allocs[n] { continue }
            dk := "none"
            switch {
            case value == "":                                  dk = "none"
            case strings.contains(value, "temp_allocator"):    dk = "temp"
            case strings.contains(value, "context.allocator"): dk = "default"
            case:                                              dk = "custom"
            }
            append(out, ParamDefault{ name = n, kind = dk })
        }
    }
}

// _named_results collects the names of a procedure's named results: -> (result: T, err: E).
@(private="file")
_named_results :: proc(decl: TSNode, lines: []string, out: ^map[string]bool) {
    for k in _named(decl) {
        if _ntype(k) != "procedure" { continue }
        for p in _named(k) {
            if _ntype(p) != "type" { continue }
            for t in _named(p) {
                if _ntype(t) != "tuple_type" { continue }
                // `-> (n: int, a, b: []f32)`: the grammar reads `a` as a bare type node followed by the
                // named_type `b: []f32`, so bare names count once a named_type follows them.
                pending := make([dynamic]string, context.temp_allocator)
                for nt in _named(t) {
                    switch _ntype(nt) {
                    case "type":
                        tk := _named(nt)
                        if len(tk) == 1 && _ntype(tk[0]) == "identifier" { append(&pending, _text(tk[0], lines)) }
                    case "named_type":
                        for id in _named(nt) { if _ntype(id) == "identifier" { out[_text(id, lines)] = true; break } }
                        for n in pending { out[n] = true }
                        clear(&pending)
                    }
                }
            }
        }
    }
}

// _call_parts splits a call into qualifier and name. `mem.alloc(n)` parses as a
// member_expression whose last child is the call; a bare call has no such parent.
@(private="file")
_call_parts :: proc(call: TSNode, lines: []string) -> (qual, name: string, fn: TSNode, ok: bool) {
    kids := _named(call)
    if len(kids) == 0 || _ntype(kids[0]) != "identifier" { return }
    fn = kids[0]
    name = _text(fn, lines)
    parent := ts_node_parent(call)
    if !ts_node_is_null(parent) && _ntype(parent) == "member_expression" {
        pk := _named(parent)
        if len(pk) == 2 && _same(pk[1], call) && _ntype(pk[0]) == "identifier" {
            qual = _text(pk[0], lines)
        }
    }
    ok = true
    return
}

// _rhs_allocates says whether an expression is itself an allocating call (make, new, ...).
@(private="file")
_rhs_allocates :: proc(n: TSNode, lines: []string) -> bool {
    call := n
    if _ntype(n) == "member_expression" {
        k := _named(n)
        if len(k) == 2 { call = k[1] }
    }
    if _ntype(call) != "call_expression" { return false }
    qual, name, _, ok := _call_parts(call, lines)
    if !ok { return false }
    _, is_alloc := _alloc_api(qual, name)
    return is_alloc
}

// _lift climbs out of the wrappers that pass a value through unchanged -- a cast, parentheses,
// `or_return`, `or_else fallback` -- so `p := cast(^T)(mem.alloc(n) or_else panic("OOM"))` binds p.
@(private="file")
_lift :: proc(n: TSNode, lines: []string) -> TSNode {
    cur := n
    for {
        p := ts_node_parent(cur)
        if ts_node_is_null(p) { return cur }
        pk := _named(p)
        switch _ntype(p) {
        case "cast_expression", "parenthesized_expression", "or_return_expression":
            cur = p
            continue
        case "binary_expression":
            if len(pk) > 0 && _same(pk[0], cur) {
                // the operator sits between the operands: look at the text right after the left one
                ep := ts_node_end_point(cur)
                if int(ep.row) < len(lines) {
                    rest := strings.trim_left_space(lines[ep.row][min(int(ep.column), len(lines[ep.row])):])
                    if strings.has_prefix(rest, "or_else") { cur = p; continue }
                }
            }
        case "call_expression":
            // (^T)(value): a conversion written as a call whose callee is a type
            if len(pk) > 1 && _ntype(pk[0]) == "cast_expression" && !_same(pk[0], cur) { cur = p; continue }
        }
        return cur
    }
}

// _enclosing_block_end is the end of the block a statement sits in: where a name declared by it stops existing.
@(private="file")
_enclosing_block_end :: proc(n: TSNode) -> u32 {
    cur := ts_node_parent(n)
    for !ts_node_is_null(cur) {
        if _ntype(cur) == "block" { return u32(ts_node_end_byte(cur)) }
        if _ntype(cur) == "procedure_declaration" { break }
        cur = ts_node_parent(cur)
    }
    return ~u32(0)
}

@(private="file")
_in_ranges :: proc(at: u32, ranges: [dynamic][2]u32) -> bool {
    for r in ranges { if at >= r[0] && at < r[1] { return true } }
    return false
}

// _under_defer reports whether a node sits inside a defer statement of its procedure.
@(private="file")
_under_defer :: proc(n: TSNode) -> bool {
    cur := ts_node_parent(n)
    for !ts_node_is_null(cur) {
        switch _ntype(cur) {
        case "defer_statement":     return true
        case "procedure_declaration": return false
        }
        cur = ts_node_parent(cur)
    }
    return false
}

// _classify_use says what a use of a value does with it, by looking at where the use sits.
// "" means "not an ownership event" (a left-hand side, a field or element read, a length).
@(private="file")
_classify_use :: proc(node: TSNode, lines: []string, x: ^CrossInfo, results: map[string]bool) -> string {
    cur := node
    as_key := false   // the value sits in an index position: m[strings.clone(k)] = v
    for {
        p := ts_node_parent(cur)
        if ts_node_is_null(p) { return "" }
        switch _ntype(p) {
        case "call_expression":
            kids := _named(p)
            if len(kids) > 0 && _same(kids[0], cur) { return "" }   // the callee, not an argument
            qual, name, fn, ok := _call_parts(p, lines)
            if !ok { return "passed" }
            if _is_free_name(name) { return "freed_deferred" if _under_defer(p) else "freed" }
            if x != nil {
                // a procedure that frees the argument it is given (found by an earlier round)
                fp := ts_node_start_point(fn)
                if info, has := x.calls[{int(fp.row) + 1, int(fp.column)}]; has && !_has_named_args(p) {
                    for k, idx in kids {
                        if idx == 0 || !_same(k, cur) || idx - 1 >= 64 { continue }
                        bit := u64(1) << u64(idx - 1)
                        if info.sink_mask & bit != 0 { return "freed_deferred" if _under_defer(p) else "freed" }
                        if info.keep_mask & bit != 0 { return "stored" }   // the callee keeps it: no longer the caller's
                        if info.read_mask & bit != 0 { return "" }         // the callee only looks: still the caller's
                    }
                }
            }
            if _stores_arg(name) {
                if len(kids) > 1 && _same(kids[1], cur) { return "" }   // appending TO the value, not storing it
                return "stored"
            }
            if _transparent(qual, name) { cur = p; continue }   // an alias of the same memory: judge what happens to the result
            if name == "panic" { return "passed" }   // the process ends: nothing to leak
            if _reads_only(qual, name) { return "" }
            return "passed"
        case "return_statement":
            return "returned"
        case "assignment_statement":
            lhs, rhs := _assign_split(_named(p))
            if len(rhs) == 0 { return "" }
            if ts_node_start_byte(cur) < ts_node_start_byte(rhs[0]) {   // left-hand side
                return "stored" if as_key else ""                        // a map key is kept by the map
            }
            j := 0
            for r, idx in rhs { if _same(r, cur) { j = idx } }
            target := lhs[j] if len(lhs) == len(rhs) else lhs[0]
            if _ntype(target) == "identifier" {
                if _text(target, lines) == "_" { return "" }   // `_ = x` discards the value
                if _text(target, lines) in results { return "returned" }   // a named result
                return "passed"                                  // copied into another local: alias, not tracked
            }
            return "stored"                                          // a field, an element, a global through a path
        case "member_expression", "index_expression":
            pk := _named(p)
            if len(pk) > 0 && _same(pk[0], cur) {
                // &xs[0] and &p.field point into the same memory; plain p.x and p[i] only read it
                gp := ts_node_parent(p)
                if !ts_node_is_null(gp) && _ntype(gp) == "unary_expression" && strings.has_prefix(_text(gp, lines), "&") {
                    cur = p
                    continue
                }
                return ""
            }
            if _ntype(p) == "index_expression" { as_key = true }
        case "struct_field":
            sk := _named(p)
            if len(sk) >= 2 && _same(sk[0], cur) { return "" }   // the field's name, not its value
            // the value now lives in a composite: follow the composite to wherever it goes
        case "var_declaration":
            vk := _named(p)
            if len(vk) > 1 && _same(vk[len(vk) - 1], cur) { return "passed" }   // buf: T = value
            return ""
        case "binary_expression", "if_statement", "for_statement", "switch_statement", "when_statement":
            return ""   // a comparison or a condition reads the value
        case "block", "procedure", "source_file", "procedure_declaration":
            return ""
        }
        cur = p   // unary_expression, slice_expression, struct literal, parentheses ...
    }
}

@(private="file")
_rank :: proc(d: string) -> int {
    switch d {
    case "freed_deferred": return 6
    case "returned":       return 5   // a factory, even if an error path frees it
    case "stored":         return 4
    case "freed":          return 3
    case "passed":         return 2
    }
    return 0
}

// _type_name reads the type out of the first argument of make/new: `Foo`, `pkg.Foo`, `[]Foo`,
// `^Foo`, `[dynamic]Foo`. A map or anything computed yields "".
@(private="file")
_type_name :: proc(n: TSNode, lines: []string) -> string {
    switch _ntype(n) {
    case "identifier", "member_expression":
        return _text(n, lines)
    case "array_type", "pointer_type", "slice_type", "dynamic_array_type", "type", "parenthesized_expression", "unary_expression":
        for k in _named(n) {
            if r := _type_name(k, lines); r != "" { return r }
        }
    }
    return ""
}

// _allocator_of finds the allocator argument of an allocating call, if one was passed.
@(private="file")
_allocator_of :: proc(call: TSNode, lines: []string, param_allocs: map[string]bool, locals: map[string]string, ctx_override: bool) -> (kind, expr: string) {
    found := false
    seen_fn := false
    prev: TSNode
    after_eq := false
    for i in 0 ..< int(ts_node_child_count(call)) {
        c := ts_node_child(call, u32(i))
        if !bool(ts_node_is_named(c)) {
            if _ntype(c) == "=" { after_eq = true }
            continue
        }
        if !seen_fn { seen_fn = true; prev = c; continue }   // the callee
        if after_eq {                                         // `allocator = value`
            after_eq = false
            if _text(prev, lines) == "allocator" { expr = _text(c, lines); found = true }
            prev = c
            continue
        }
        lower := strings.to_lower(_text(c, lines), context.temp_allocator)
        if strings.contains(lower, "allocator") || strings.contains(lower, "arena") || _text(c, lines) in locals || param_allocs[_text(c, lines)] {
            expr = _text(c, lines)
            found = true
        }
        prev = c
    }

    kind = "default"
    if found {
        switch {
        case strings.contains(expr, "temp_allocator"):                         kind = "temp"
        case expr == "context.allocator", strings.contains(expr, "default_allocator"): kind = "default"
        case param_allocs[expr]:                                               kind = "param"
        case expr in locals:                                                   kind = locals[expr]
        case:                                                                  kind = "custom"
        }
    }
    if kind == "default" && ctx_override { kind = "custom" }   // context.allocator was reassigned in this procedure
    return
}

// =============================================================================
// The analysis
// =============================================================================

// ownership_analyze reads one procedure_declaration and returns its allocation sites.
ownership_analyze :: proc(decl: TSNode, lines: []string, x: ^CrossInfo = nil) -> ProcOwnership {
    out := ProcOwnership{
        sites = make([dynamic]AllocSite, context.temp_allocator),
        sinks = make([dynamic]int, context.temp_allocator),
        effects = make([dynamic]ParamEffect, context.temp_allocator),
        defaults = make([dynamic]ParamDefault, context.temp_allocator),
    }
    body, params := _proc_parts(decl)
    if ts_node_is_null(body) { return out }   // a foreign declaration has no body

    c := Collected{
        calls   = make([dynamic]TSNode, context.temp_allocator),
        idents  = make([dynamic]TSNode, context.temp_allocator),
        assigns = make([dynamic]TSNode, context.temp_allocator),
        decls   = make([dynamic]TSNode, context.temp_allocator),
    }
    _collect(body, &c)

    param_allocs := _param_allocators(params, lines)
    _param_default_kinds(params, lines, param_allocs, &out.defaults)
    ctx_override := false
    for a in c.assigns {
        k := _named(a)
        if len(k) > 0 && _text(k[0], lines) == "context.allocator" { ctx_override = true }
    }

    // Names declared in this procedure; an assignment to any other name reaches outside it.
    declared := make(map[string]bool, context.temp_allocator)
    results  := make(map[string]bool, context.temp_allocator)
    if !ts_node_is_null(params) {
        for par in _named(params) {
            for k in _named(par) { if _ntype(k) == "identifier" { declared[_text(k, lines)] = true } }
        }
    }
    _named_results(decl, lines, &results)
    for r in results { declared[r] = true }
    for a in c.assigns {
        lhs, rhs := _assign_split(_named(a))
        if !_is_decl_assign(lhs, rhs, lines) { continue }
        for l in lhs { if _ntype(l) == "identifier" { declared[_text(l, lines)] = true } }
    }
    for d in c.decls {
        for k in _named(d) { if _ntype(k) == "identifier" { declared[_text(k, lines)] = true; break } }
    }

    // Locals that hold an allocator: `a := mem.arena_allocator(arena)`, `s := context.temp_allocator`.
    locals := make(map[string]string, context.temp_allocator)
    for a in c.assigns {
        lhs, rhs := _assign_split(_named(a))
        for r, idx in rhs {
            if len(lhs) != len(rhs) { break }
            if _ntype(lhs[idx]) != "identifier" { continue }
            txt := _text(r, lines)
            low := strings.to_lower(txt, context.temp_allocator)
            if !strings.contains(low, "allocator") && !strings.contains(low, "arena") { continue }
            if _rhs_allocates(r, lines) { continue }
            switch {
            case strings.contains(txt, "temp_allocator"):  locals[_text(lhs[idx], lines)] = "temp"
            case txt == "context.allocator":                locals[_text(lhs[idx], lines)] = "default"
            case param_allocs[txt]:                         locals[_text(lhs[idx], lines)] = "param"
            case:                                           locals[_text(lhs[idx], lines)] = "custom"
            }
        }
    }

    // Pass 1: the allocation sites, with how the result is bound.
    ends := make([dynamic]u32, context.temp_allocator)   // end byte of each site's expression
    scope_ends   := make([dynamic]u32, context.temp_allocator)   // where the name the site binds stops existing
    stmt_starts  := make([dynamic]u32, context.temp_allocator)   // start of the declaring statement
    is_decls     := make([dynamic]bool, context.temp_allocator)  // the name is declared there (`:=`), not assigned
    block_ends   := make([dynamic]u32, context.temp_allocator)   // end of the block the binding statement sits in
    for call in c.calls {
        qual, name, fn, ok := _call_parts(call, lines)
        if !ok { continue }
        if _is_free_name(name) { out.free_calls += 1 }
        api, is_alloc := _alloc_api(qual, name)
        cc: CrossCall
        via_call := false
        if !is_alloc && x != nil {
            // a call to a project procedure that returns memory it allocated (found by an earlier round)
            fp := ts_node_start_point(fn)
            if info, has := x.calls[{int(fp.row) + 1, int(fp.column)}]; has && info.factory {
                cc = info
                via_call = true
                is_alloc = true
                api = strings.concatenate({name, "()"}, context.temp_allocator)
            }
        }
        if !is_alloc { continue }

        raw := call
        if qual != "" { raw = ts_node_parent(call) }
        pt := ts_node_start_point(raw)
        expr := _lift(raw, lines)
        site := AllocSite{
            api       = api,
            elem_type = "",
            line      = int(pt.row) + 1,
            col       = int(pt.column),
        }
        if via_call {
            site.via = cc.callee
            if cc.factory_kind == "param" {
                site.allocator_kind, site.allocator_expr = _allocator_of(call, lines, param_allocs, locals, ctx_override)
                if site.allocator_expr == "" {
                    // nothing passed: the factory's own default decides (temp_allocator for read_slice)
                    switch cc.default_kind {
                    case "temp":   site.allocator_kind = "temp"
                    case "custom": site.allocator_kind = "custom"
                    }
                }
            } else {
                site.allocator_kind = "custom" if ctx_override else "default"
            }
            // the type is named in the factory's package; from here it is reached through the same qualifier
            switch {
            case cc.elem_type == "":
            case strings.contains(cc.elem_type, "."):
            case qual != "":  site.elem_type = strings.concatenate({qual, ".", cc.elem_type}, context.temp_allocator)
            case:             site.elem_type = cc.elem_type
            }
        } else {
            site.allocator_kind, site.allocator_expr = _allocator_of(call, lines, param_allocs, locals, ctx_override)
            if kids := _named(call); len(kids) >= 2 && (api == "make" || api == "new" || api == "mem.new") {
                site.elem_type = _type_name(kids[1], lines)
            }
        }

        // How is the result bound? `x := make(...)` binds a name; anything else is decided at once.
        site.disposition = ""
        site_scope_end := ~u32(0)
        site_stmt_start := u32(0)
        site_is_decl := false
        site_block_end := ~u32(0)
        par := ts_node_parent(expr)
        if !ts_node_is_null(par) && _ntype(par) == "assignment_statement" {
            lhs, rhs := _assign_split(_named(par))
            for r, idx in rhs {
                if !_same(r, expr) { continue }
                target := lhs[idx] if len(lhs) == len(rhs) else lhs[0]
                switch {
                case _ntype(target) != "identifier":
                    site.disposition = "stored"
                case _text(target, lines) in results:
                    site.disposition = "returned"                 // a named result
                case !(_text(target, lines) in declared):
                    site.disposition = "stored"                   // a global or an outer variable
                case:
                    site.var_name = _text(target, lines)
                    site_block_end = _enclosing_block_end(par)
                    if _is_decl_assign(lhs, rhs, lines) {
                        site_is_decl = true
                        site_scope_end = _enclosing_block_end(par)
                        site_stmt_start = u32(ts_node_start_byte(par))
                    }
                }
            }
        } else if !ts_node_is_null(par) && _ntype(par) == "var_declaration" {
            vk := _named(par)
            if len(vk) > 1 && _same(vk[len(vk) - 1], expr) && _ntype(vk[0]) == "identifier" {
                site.var_name = _text(vk[0], lines)
                site_block_end = _enclosing_block_end(par)
                site_is_decl = true
                site_scope_end = _enclosing_block_end(par)
                site_stmt_start = u32(ts_node_start_byte(par))
            }
        }
        if site.var_name == "" && site.disposition == "" {
            site.disposition = _classify_use(expr, lines, x, results)
            if site.disposition == "" { site.disposition = "unfreed" }   // a result that is dropped
        }
        // `new(T)` in a generic procedure names a type parameter, not a type of the project
        if site.elem_type != "" && site.elem_type in declared { site.elem_type = "" }
        append(&out.sites, site)
        append(&ends, ts_node_end_byte(expr))
        append(&scope_ends, site_scope_end)
        append(&stmt_starts, site_stmt_start)
        append(&is_decls, site_is_decl)
        append(&block_ends, site_block_end)
    }

    // Pass 2: for each bound name, the strongest thing that later happens to it.
    for &site, i in out.sites {
        if site.var_name == "" { continue }
        // A use belongs to this site if it comes after it, inside the block the name was declared in, before
        // the name is bound again in that block, and not inside a nested block that declares the name anew.
        limit := scope_ends[i]
        excl := make([dynamic][2]u32, context.temp_allocator)
        for j in 0 ..< len(out.sites) {
            if j == i || out.sites[j].var_name != site.var_name || ends[j] <= ends[i] { continue }
            if is_decls[j] && scope_ends[j] < scope_ends[i] {
                append(&excl, [2]u32{stmt_starts[j], scope_ends[j]})
            } else if !is_decls[j] && block_ends[j] != block_ends[i] {
                // `name = ...` in a sibling or nested block (an if / else, a loop body) does not replace this
                // one for the code after it: whichever ran, the later uses apply to both
            } else if ends[j] < limit {
                limit = ends[j]
            }
        }
        // local copies (`q := p`) are the same memory: follow them
        names := make(map[string]bool, context.temp_allocator)
        names[site.var_name] = true
        absorbed := make(map[u32]bool, context.temp_allocator)   // the right-hand sides of those copies
        for _ in 0 ..< 3 {
            changed := false
            for a in c.assigns {
                lhs, rhs := _assign_split(_named(a))
                if len(lhs) != len(rhs) { continue }
                for r, idx in rhs {
                    if _ntype(r) != "identifier" || !(_text(r, lines) in names) { continue }
                    sb := u32(ts_node_start_byte(r))
                    if sb < ends[i] || sb >= limit || sb in absorbed || _in_ranges(sb, excl) { continue }
                    if _ntype(lhs[idx]) != "identifier" { continue }
                    copy_name := _text(lhs[idx], lines)
                    if copy_name == "_" || copy_name in results || !(copy_name in declared) { continue }
                    names[copy_name] = true
                    absorbed[sb] = true
                    changed = true
                }
            }
            if !changed { break }
        }
        best := 0
        disp := ""
        for id in c.idents {
            if !(_text(id, lines) in names) { continue }
            sb := u32(ts_node_start_byte(id))
            if sb < ends[i] || sb >= limit || sb in absorbed || _in_ranges(sb, excl) { continue }
            d := _classify_use(id, lines, x, results)
            if r := _rank(d); r > best { best = r; disp = d }
        }
        site.disposition = disp if best > 0 else "unfreed"
    }

    // Parameters this procedure frees: it takes ownership of what it is given.
    if !ts_node_is_null(params) {
        idx := 0
        for par in _named(params) {
            kind := _ntype(par)
            if kind != "parameter" && kind != "default_parameter" { continue }
            for k in _named(par) {
                if _ntype(k) != "identifier" { continue }
                pname := _text(k, lines)
                freed, kept, unknown := false, false, false
                for id in c.idents {
                    if _text(id, lines) != pname { continue }
                    switch _classify_use(id, lines, x, results) {
                    case "freed", "freed_deferred": freed = true
                    case "returned", "stored":      kept = true
                    case "passed":                  unknown = true
                    }
                }
                switch {
                case freed:   append(&out.sinks, idx)
                case unknown: // handed on to something we cannot see into: no claim
                case kept:    append(&out.effects, ParamEffect{ idx = idx, effect = "kept" })
                case:         append(&out.effects, ParamEffect{ idx = idx, effect = "read" })
                }
                idx += 1
            }
        }
    }
    return out
}
