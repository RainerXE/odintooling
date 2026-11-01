package pool

// Same package name, same procedure name and same type name as ../lib: a different procedure.
Slab :: struct { n: int }

slab_new :: proc(allocator := context.allocator) -> ^Slab {
	return new(Slab, allocator)
}
