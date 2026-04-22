package c101_edge

import "core:mem"

// EDGE: suppression comment silences the rule
proc_suppressed :: proc(alloc: mem.Allocator) {
    context.allocator = alloc  // odin-lint:ignore C101
}

// EDGE: comment mentioning context.allocator = should not trigger
proc_comment_only :: proc() {
    // context.allocator = something  (this is just a comment, not real code)
    _ = 1
}

// EDGE: nested proc literal inside outer — outer has no violation, inner is checked separately
proc_outer_clean :: proc() {
    // outer proc does not assign context.allocator
    inner :: proc(alloc: mem.Allocator) {
        old := context.allocator
        context.allocator = alloc
        defer context.allocator = old  // inner is clean too
    }
    inner(context.allocator)
}
