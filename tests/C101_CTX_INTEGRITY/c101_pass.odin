package c101_pass

import "core:mem"

// PASS: proper defer restore pattern
proc_with_defer_restore :: proc(alloc: mem.Allocator) {
    old := context.allocator
    context.allocator = alloc
    defer context.allocator = old
}

// PASS: temp_allocator with defer restore
proc_temp_with_restore :: proc(alloc: mem.Allocator) {
    old := context.temp_allocator
    context.temp_allocator = alloc
    defer context.temp_allocator = old
}

// PASS: reading context.allocator (not writing)
proc_read_only :: proc() {
    _ = context.allocator
}

// PASS: context shadow copy — modification is local
proc_shadow_copy :: proc(alloc: mem.Allocator) {
    context := context
    context.allocator = alloc
}

// PASS: proc that never touches context.allocator
proc_unrelated :: proc() -> int {
    return 42
}
