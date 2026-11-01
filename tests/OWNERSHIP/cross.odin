package own

import "lib"

// A factory in another package, released by its partner: nothing leaks.
slab_ok :: proc() {
	s := pool.slab_new()
	defer pool.slab_release(s)
}

// ... never released: a leak candidate that only the cross-procedure pass can see.
slab_leak :: proc() {
	s := pool.slab_new()
	_ = s
}

// ... from the temp allocator: nothing owed.
slab_temp :: proc() {
	s := pool.slab_new(context.temp_allocator)
	_ = s
}

// A wrapper around a factory is a factory (found on a later round) ...
wrapper :: proc() -> ^Thing {
	return thing_create("w")
}

// ... so its callers own what it returns.
wrapper_leak :: proc() {
	t := wrapper()
	_ = t
}

wrapper_ok :: proc() {
	t := wrapper()
	defer thing_destroy(t)
}

// consume frees its parameter, so handing it a pointer is a release, not a leak.
hand_over :: proc() {
	n := new(Node)
	consume(n)
}

// ... and so does a procedure that only passes it on to one that does.
consume_via :: proc(n: ^Node) {
	consume(n)
}
hand_over_twice :: proc() {
	n := new(Node)
	consume_via(n)
}

// storing is still storing, whatever consume does elsewhere
keeps :: proc(holder: ^Registry) {
	t := wrapper()
	append(&holder.things, t)
}

// A factory whose results nobody ever releases (the project's convention, e.g. an arena or a parent
// that owns its children): not freeing its result is no evidence of a leak.
Widget :: struct { id: int }
widget_new :: proc() -> ^Widget {
	return new(Widget)
}
widget_a :: proc() {
	w := widget_new()
	_ = w
}
widget_b :: proc() {
	w := widget_new()
	_ = w
}

// no allocator passed: the factory's default (temp) decides, so nothing is owed ...
scratch_default :: proc() {
	s := pool.slab_scratch()
	_ = s
}
// ... and passing the default allocator explicitly makes it the caller's to free.
scratch_explicit :: proc() {
	s := pool.slab_scratch(context.allocator)
	_ = s
}
