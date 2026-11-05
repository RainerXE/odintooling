package c001_ownership

// Each of these must still be reported (line numbers are checked by the test runner).

// never freed, returned or stored                                  -> line 7
leaks :: proc(n: int) {
	buf := make([]int, n)
	buf[0] = 1
}

// only read                                                        -> line 13
reads :: proc() -> int {
	xs := make([]int, 4)
	total := 0
	for x in xs { total += x }
	return total
}

// assigned and dropped                                             -> line 21
mixed :: proc() {
	a := make([]int, 2)
	_ = a
}

// `return len(xs)` is not a return of xs
return_len :: proc() -> int {
	xs := make([]int, 4)
	return len(xs)
}

// a parameter allocator is the caller's, not an arena: freeing is still owed
param_allocator :: proc(allocator := context.allocator) -> int {
	buf := make([]int, 4, allocator)
	buf[0] = 1
	return 0
}

// a split declaration that leaks is reported at its first line
split_leak :: proc() {
	buf :=
		make([]int, 4)
	buf[0] = 1
}

// a result thrown away with the blank identifier: nothing can free it
blank_discard :: proc() {
	_ = make([]int, 4)
}
