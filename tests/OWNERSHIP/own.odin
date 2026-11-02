package own

import "core:mem"
import "core:strings"
import "core:fmt"

Thing :: struct { name: string, data: []byte }
Node  :: struct { next: ^Node }
Registry :: struct { things: [dynamic]^Thing, cache: []int }

registry: Registry

// factory: the caller owns the result
thing_create :: proc(name: string, allocator := context.allocator) -> ^Thing {
	t := new(Thing, allocator)
	t.name = strings.clone(name, allocator)
	return t
}

// allocates and frees in the same proc, deferred
roundtrip :: proc() {
	buf := make([]byte, 64)
	defer delete(buf)
	_ = buf
}

// frees on one path, hands over on the other
conditional :: proc(fail: bool) -> ^Thing {
	t := new(Thing)
	if fail {
		free(t)
		return nil
	}
	return t
}

// default allocator, never freed: the leak candidate
leaks :: proc() {
	buf := make([]int, 10)
	buf[0] = 1
	fmt.println(len(buf))
}

// temp allocator: nothing owed
scratch :: proc() -> int {
	tmp := make([]int, 8, context.temp_allocator)
	return len(tmp)
}

// custom (an arena the caller supplies)
with_arena :: proc(arena: ^mem.Arena) {
	a := mem.arena_allocator(arena)
	n := new(Node, a)
	_ = n
}

// stored into a long-lived structure
register :: proc() {
	t := new(Thing)
	append(&registry.things, t)
	registry.cache = make([]int, 4)
}

// handed to another procedure
passes :: proc() {
	n := new(Node)
	consume(n)
}

consume :: proc(n: ^Node) { free(n) }

// freed by a destroy-style helper
cleanup :: proc() {
	t := thing_create("x")
	defer thing_destroy(t)
}

thing_destroy :: proc(t: ^Thing) {
	delete(t.name)
	free(t)
}

// the allocator is a parameter: the caller of THIS proc owns the result
with_param :: proc(allocator: mem.Allocator) -> []int {
	return make([]int, 3, allocator)
}

// multi-value binding
read_all :: proc() {
	data, ok := os_read("x")
	_ = ok
	other, other2 := new(int), new(int)
	free(other)
	_ = other2
}
os_read :: proc(p: string) -> ([]byte, bool) { return nil, false }

// reassigning context.allocator makes every default allocation custom
with_context :: proc(a: mem.Allocator) {
	context.allocator = a
	x := make([]int, 2)
	_ = x
}

// nested named proc is analysed on its own, not as part of its parent
outer :: proc() {
	inner :: proc() {
		z := new(int)
		_ = z
	}
	y := new(int)
	free(y)
	inner()
}

// an assignment to a global is a store, not a local that must be freed
g_state: ^Thing
init_global :: proc() {
	g_state = new(Thing)
}

// a map key is kept by the map
index_key :: proc(m: ^map[string]int, k: string) {
	m[strings.clone(k)] = 1
}

// a named result is returned
named_result :: proc(n: int) -> (result: []int) {
	result = make([]int, n)
	return
}

// aliased into a composite value: ownership is not followed
into_struct :: proc() {
	bytes := make([]byte, 8)
	buf: Registry = {cache = nil}
	other := Thing{data = bytes}
	_ = buf
	_ = other
}

// only read: still unfreed
read_only :: proc() {
	xs := make([]int, 4)
	if xs != nil { fmt.println(len(xs)) }
}

// wrappers around the allocation do not hide the binding
wrapped :: proc(a: mem.Allocator) {
	res := cast(^Thing)(mem.alloc(8, 8, a) or_else panic("OOM"))
	free(res)
}

// several named results under one type are all results
named_pair :: proc(n: int) -> (count: int, left, right: []int) {
	count = n
	left = make([]int, n)
	right = make([]int, n)
	return
}

// raw_data and conversions pass the memory through: returning them returns it
alias_return :: proc() -> cstring {
	buf := make([]u8, 8)
	return cstring(raw_data(buf))
}
result_alias :: proc() -> (ws: rawptr) {
	t := make([]u16, 2)
	ws = cast(rawptr)raw_data(t)
	return
}

// only the printing procedures of fmt just look at their arguments
registered :: proc() {
	fmt.set_user_formatters(new(map[typeid]int))
}
printed :: proc() {
	fmt.println(new(int))
}

// a local copy is the same memory
alias_freed :: proc() {
	p := new(int)
	q := p
	free(q)
}
alias_returned :: proc() -> ^int {
	p := new(int)
	q := p
	return q
}
alias_leak :: proc() {
	p := new(int)
	q := p
	_ = q
}

// a composite carries the memory to wherever the composite goes
literal_returned :: proc() -> Registry {
	cache := make([]int, 4)
	return Registry{cache = cache}
}

// &xs[0] points into the allocation; xs[0] only reads it
addr_returned :: proc() -> ^int {
	xs := make([]int, 4)
	return &xs[0]
}
index_read :: proc() -> int {
	xs := make([]int, 4)
	return xs[0]
}

// the same name in a nested block is a different allocation
shadow_outer :: proc(flag: bool) {
	x := make([]int, 2)
	if flag {
		x := make([]int, 3)
		defer delete(x)
	}
	delete(x)
}
shadow_inner_leak :: proc(flag: bool) {
	x := make([]int, 2)
	defer delete(x)
	if flag {
		x := make([]int, 3)
		x[0] = 1
	}
}

// the same name in sibling branches: each is its own allocation
siblings :: proc(flag: bool) {
	if flag {
		buf := make([]u8, 1)
		defer delete(buf)
	} else {
		buf := make([]u8, 2)
		buf[0] = 1
	}
}

// a closure's allocation belongs to the closure's own scope, not the procedure's
with_closure :: proc() {
	f := proc() {
		z := new(int)
		free(z)
	}
	f()
}

// an if-initialiser allocation
if_init :: proc() {
	if buf := make([]int, 2); len(buf) > 0 {
		delete(buf)
	}
}

// a type parameter is not a type of the project
generic_new :: proc($T: typeid) -> ^T {
	return new(T)
}

// a procedure group of factories is a factory
make_a :: proc() -> ^Thing { return new(Thing) }
make_b :: proc(n: int) -> ^Thing { return new(Thing) }
make_any :: proc{make_a, make_b}
group_leak :: proc() {
	t := make_any()
	_ = t
}
group_ok :: proc() {
	t := make_any(1)
	defer free(t)
}

// assigned in both branches, freed once afterwards: both allocations are freed
branch_assign :: proc(flag: bool) {
	name: []int
	if flag {
		name = make([]int, 1)
	} else {
		name = make([]int, 2)
	}
	delete(name)
}

// assigned in a branch only, then dropped: still a leak
branch_leak :: proc(flag: bool) {
	name: []int
	if flag {
		name = make([]int, 1)
	}
	_ = name
}

// rebound in the same block: the first is replaced before it is freed, the second is freed
rebound :: proc() {
	name: []int
	name = make([]int, 1)
	name = make([]int, 2)
	delete(name)
}
