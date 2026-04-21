package c012_t1_test

import "core:mem"

// C012-T1 PASS cases — correctly named allocator variables
// All should produce zero C012 violations.

// Has "alloc" in name — ok
frame_alloc: mem.Allocator

// Has "allocator" in name — ok
scratch_allocator: mem.Allocator

// Has "alloc" as part of longer name — ok
arena_alloc_backing: mem.Allocator
