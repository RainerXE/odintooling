package defer_block

// Every allocation here is released by a deferred block, so C001 must stay quiet.
benchmark :: proc(size: int) {
	left  := make([]u8, size)
	right := make([]u8, size)
	defer {
		delete(left)
		delete(right)
	}
	_ = left
	_ = right
}
