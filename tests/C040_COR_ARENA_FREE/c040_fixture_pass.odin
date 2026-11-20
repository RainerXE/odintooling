package c040_pass

import "core:mem"

ARENA_SIZE :: 4096

// The default allocator: the caller owns this memory, so the free is real.
heap_slice :: proc() {
	buf := make([]u8, 32)
	defer delete(buf)
	_ = buf
}

// Arena memory with no per-allocation free: the arena owns it.
arena_no_free :: proc() {
	backing := make([]u8, ARENA_SIZE)
	defer delete(backing)
	arena: mem.Arena
	mem.arena_init(&arena, backing)
	xs := make([]u8, 16, mem.arena_allocator(&arena))
	_ = xs
}

// A capacity is not an allocator: these use the default allocator.
dynamic_default :: proc() {
	xs := make([dynamic]int, 0, 8)
	defer delete(xs)
	_ = xs
}

map_default :: proc() {
	m := make(map[string]int, 8)
	delete(m)
}

// Suppressed on the allocation line.
suppressed_temp :: proc() {
	buf := make([]u8, 8, context.temp_allocator) // olt:ignore C040 deliberate
	defer delete(buf)
	_ = buf
}
