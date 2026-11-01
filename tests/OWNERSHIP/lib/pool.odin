package pool

Slab :: struct { n: int }

// a factory whose allocator the caller chooses
slab_new :: proc(allocator := context.allocator) -> ^Slab {
	s := new(Slab, allocator)
	s.n = 1
	return s
}

// releases what slab_new made
slab_release :: proc(s: ^Slab) {
	free(s)
}

// a factory whose allocator defaults to the temp allocator: with no argument, nothing is owed
slab_scratch :: proc(allocator := context.temp_allocator) -> ^Slab {
	return new(Slab, allocator)
}
