package graph_test

import "core:mem"

// M7 test fixture — verifies graph enrichment features.

// Package-level allocator-typed variable — must be indexed with memory_role='allocator'.
scratch_allocator: mem.Allocator

// Package-level plain variable — must be indexed with no memory_role.
frame_count: int = 0

// Proc that returns mem.Allocator — must be tagged memory_role='allocator' via return_type.
get_scratch :: proc() -> mem.Allocator {
    return scratch_allocator
}

// Proc that returns a plain type — must NOT be tagged as allocator.
get_frame_count :: proc() -> int {
    return frame_count
}

// Local var inside a proc — must NOT appear in nodes table at all.
do_work :: proc() {
    local_alloc: mem.Allocator = scratch_allocator
    _ = local_alloc
    local_count := 42
    _ = local_count
}
