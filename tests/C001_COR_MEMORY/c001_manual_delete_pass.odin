package c001_manual_delete_pass

// C001 PASS fixture — direct (non-deferred) delete/free
//
// All allocations here have a matching direct delete call in the same block.
// Expected: ZERO C001 violations.
//
// Regression for the is_free_call / has_manual_cleanup bug where the Odin
// tree-sitter grammar has no argument_list or expression_statement wrappers,
// so direct deletes were silently ignored and always flagged as leaks.

// Case 1: single delete at end of proc.
single_delete :: proc() {
    buf := make([]u8, 256)
    _ = buf
    delete(buf)
}

// Case 2: two allocations, two deletes on the same line (semicolon-separated).
two_allocs_semicolon_delete :: proc() {
    colors := make([dynamic][4]f32, 10)
    stops  := make([dynamic]f32, 10)
    _ = colors
    _ = stops
    delete(colors); delete(stops)
}

// Case 3: allocation inside an if block with direct delete before return.
alloc_in_if_with_delete :: proc(cond: bool) {
    if cond {
        data := make([]int, 100)
        _ = data
        delete(data)
    }
}

// Case 4: allocation followed by delete inside a for loop body.
alloc_and_delete_in_loop :: proc(n: int) {
    for i in 0 ..< n {
        tmp := make([]byte, 64)
        _ = tmp
        delete(tmp)
    }
}
