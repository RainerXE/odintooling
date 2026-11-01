package c001_ownership

import "core:mem"

Thing :: struct { items: [dynamic]int, buf: []int }
Registry :: struct { things: [dynamic]^Thing }

registry: Registry

// None of these should be reported: each allocation is demonstrably handed on or released elsewhere.

// returned inside a tuple, through a slice
tuple_slice :: proc(n: int) -> (int, []int, bool) {
	events := make([dynamic]int)
	for i in 0 ..< n { append(&events, i) }
	return n, events[:], true
}

// assigned to a named result
named_result :: proc(n: int) -> (count: int, buf: []int) {
	count = n
	buf = make([]int, n)
	return
}

// several named results under one type
named_pair :: proc(n: int) -> (left, right: []int) {
	left = make([]int, n)
	right = make([]int, n)
	return
}

// stored into a field of something longer-lived
store_field :: proc(t: ^Thing, n: int) {
	items := make([dynamic]int, 0, n)
	t.items = items
}

// stored by appending to a registry
store_list :: proc() {
	t := new(Thing)
	append(&registry.things, t)
}

// freed on a path the block-level rule cannot see
freed_in_branch :: proc(fail: bool) -> ^Thing {
	t := new(Thing)
	if fail {
		free(t)
		return nil
	}
	return t
}

// freed by a deferred block
freed_by_block :: proc(n: int) {
	a := make([]int, n)
	b := make([]int, n)
	defer {
		delete(a)
		delete(b)
	}
	_ = a
	_ = b
}

// drawn from an arena held in a local
from_arena :: proc(arena: ^mem.Arena) {
	a := mem.arena_allocator(arena)
	n := new(Thing, a)
	_ = n
}

// memory from the temp allocator is released wholesale
from_temp :: proc(n: int) -> int {
	tmp := make([]int, n, context.temp_allocator)
	return len(tmp)
}

// returned through raw_data and a conversion
as_cstring :: proc() -> cstring {
	buf := make([]u8, 8)
	return cstring(raw_data(buf))
}
