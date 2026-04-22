package c101_fail

import "core:mem"

// FAIL: context.allocator assigned without defer restore
proc_no_restore :: proc(alloc: mem.Allocator) {
    context.allocator = alloc    // C101
    _ = context.allocator
}

// FAIL: temp_allocator assigned without defer restore
proc_temp_no_restore :: proc(alloc: mem.Allocator) {
    context.temp_allocator = alloc    // C101
}
