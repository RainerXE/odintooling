package defer_block

// The deferred block frees `a` only: C001 must still flag `b`.
partial :: proc(size: int) {
	a := make([]u8, size)
	b := make([]u8, size)
	defer {
		delete(a)
	}
	_ = a
	_ = b
}
