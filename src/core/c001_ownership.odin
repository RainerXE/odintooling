// c001_ownership.odin — what the ownership analysis knows about the allocations C001 looks at.
//
// C001 reads one block at a time and only recognises `return x` and `defer delete(x)` as the end of
// an allocation's life. The ownership analysis (ownership.odin, the one behind the graph) follows the
// whole procedure: a slice returned inside a tuple, a result stored into a field or a list, an
// allocation released on every path, memory from an arena held in a local. C001 asks it, and stays
// quiet where the allocation is demonstrably handed on or released by its allocator.
//
// It only ever SUPPRESSES: where the analysis is unsure (`passed`, `unfreed`) C001 behaves as before.
package core

import "core:strings"
import "base:runtime"

// C001Verdict is what the analysis concluded about one allocation C001 might report.
C001Verdict :: struct {
    var_name:       string,
    disposition:    string,   // freed_deferred | freed | returned | stored | passed | unfreed
    allocator_kind: string,   // default | temp | param | custom
}

// C001Ownership holds the verdicts for one file, by the line of the allocation.
C001Ownership :: struct {
    by_line: map[int][dynamic]C001Verdict,
}

// c001_ownership_for analyses a whole file. When it cannot (the file does not parse) the answer is
// empty, so C001 behaves exactly as it did before; free the result with c001_ownership_free.
c001_ownership_for :: proc(lines: []string) -> ^C001Ownership {
    out := new(C001Ownership)
    out.by_line = make(map[int][dynamic]C001Verdict)

    source := strings.join(lines, "\n", context.temp_allocator)
    adapter, adapter_ok := initASTAdapter()
    if !adapter_ok { return out }
    defer deinitASTAdapter(adapter)

    tree, tree_ok := parseSource(adapter.parser, adapter.language, source)
    if !tree_ok { return out }
    defer ts_tree_delete(tree)
    root := getRootNode(tree)
    if ts_node_is_null(root) { return out }

    decls := make([dynamic]TSNode, context.temp_allocator)
    _collect_proc_decls(root, &decls)
    for decl in decls {
        // the analysis allocates from the temp allocator; hand it back after each procedure
        guard := runtime.default_temp_allocator_temp_begin()
        defer runtime.default_temp_allocator_temp_end(guard)

        own := ownership_analyze(decl, lines)
        for site in own.sites {
            if site.api != "make" && site.api != "new" { continue }   // the calls C001 looks at
            list := out.by_line[site.line]
            append(&list, C001Verdict{
                var_name       = strings.clone(site.var_name),
                disposition    = strings.clone(site.disposition),
                allocator_kind = strings.clone(site.allocator_kind),
            })
            out.by_line[site.line] = list
        }
    }
    return out
}

c001_ownership_free :: proc(o: ^C001Ownership) {
    if o == nil { return }
    for _, list in o.by_line {
        for v in list { delete(v.var_name); delete(v.disposition); delete(v.allocator_kind) }
        delete(list)
    }
    delete(o.by_line)
    free(o)
}

// c001_verdict_for finds the verdict for the allocation C001 sees at lines start..end bound to var_name.
// The range matters: `buf := \n    make(...)` starts on one line and its make on another.
c001_verdict_for :: proc(o: ^C001Ownership, start, end: int, var_name: string) -> (v: C001Verdict, ok: bool) {
    if o == nil { return }
    last := min(max(end, start), start + 40)
    candidates := 0
    only: C001Verdict
    for line in start ..= last {
        list, has := o.by_line[line]
        if !has { continue }
        for c in list {
            if c.var_name == var_name { return c, true }
            if c.var_name == "" { candidates += 1; only = c }
        }
    }
    if candidates == 1 { return only, true }
    return
}

// c001_handled_elsewhere says whether the analysis shows the allocation is already taken care of:
// released, returned, stored somewhere that outlives the call, or drawn from an allocator that is
// released wholesale (temp, an arena). "Passed to another procedure" is not enough: whether the callee
// frees it is exactly what C001 cannot tell.
c001_handled_elsewhere :: proc(o: ^C001Ownership, start, end: int, var_name: string) -> bool {
    v, ok := c001_verdict_for(o, start, end, var_name)
    if !ok { return false }
    switch v.disposition {
    case "freed_deferred", "freed", "returned", "stored": return true
    }
    return v.allocator_kind == "temp" || v.allocator_kind == "custom"
}

// c001_confirmed_leak says whether the analysis found nothing at all done with the allocation: memory
// from the default or a parameter allocator that is never freed, returned, stored or passed on. That is
// stronger than anything C001's own heuristics can establish, so it overrides the two of them that are
// known to be loose: "the variable appears in a return statement" (`return len(xs)` is not a return of
// xs) and "an argument mentions allocator" (a parameter allocator is the caller's, not an arena).
c001_confirmed_leak :: proc(o: ^C001Ownership, start, end: int, var_name: string) -> bool {
    v, ok := c001_verdict_for(o, start, end, var_name)
    if !ok { return false }
    return v.disposition == "unfreed" && (v.allocator_kind == "default" || v.allocator_kind == "param")
}
