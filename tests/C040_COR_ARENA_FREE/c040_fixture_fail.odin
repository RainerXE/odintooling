package c040_fail

import "core:mem"

ARENA_SIZE :: 4096

// Freeing temp memory: the temp allocator releases it wholesale.
temp_slice :: proc() {
	buf := make([]u8, 32, context.temp_allocator)
	defer delete(buf)
	_ = buf
}

temp_dynamic :: proc() {
	args := make([dynamic]string, 0, 10, context.temp_allocator)
	defer delete(args)
	_ = args
}

// Two-argument dynamic form: the allocator is the second argument.
temp_dynamic_alloc_only :: proc() {
	xs := make([dynamic]int, context.temp_allocator)
	defer delete(xs)
	_ = xs
}

// `new` + `free` is the same no-op; the rule is not delete-specific.
temp_new_free :: proc() {
	p := new(int, context.temp_allocator)
	defer free(p)
	_ = p
}

// Freeing memory from an explicit arena allocator.
arena_explicit :: proc() {
	backing := make([]u8, ARENA_SIZE)
	defer delete(backing)
	arena: mem.Arena
	mem.arena_init(&arena, backing)
	xs := make([]u8, 16, mem.arena_allocator(&arena))
	delete(xs)
	_ = xs
}

// The same, through a local holding the arena allocator.
arena_alias :: proc() {
	backing := make([]u8, ARENA_SIZE)
	defer delete(backing)
	arena: mem.Arena
	mem.arena_init(&arena, backing)
	a := mem.arena_allocator(&arena)
	xs := make([]u8, 16, a)
	delete(xs)
	_ = xs
}
