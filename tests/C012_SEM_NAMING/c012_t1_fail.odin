package c012_t1_test

import "core:mem"

// C012-T1 FAIL cases — opaquely named allocator variables
// Each should produce one C012 violation.

// Opaque name — no "alloc" hint
scratch: mem.Allocator

// Name suggests data, not an allocator
pool: mem.Allocator

// Private var, still should fire
backing: mem.Allocator
