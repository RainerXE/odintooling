package own

import "lib2"

// lib2.slab_new is not lib.slab_new: that other procedure's callers free its result, this one's never do,
// so this caller is not a leak candidate (the peers of a factory are the callers of THAT procedure).
lib2_user :: proc() {
	s := pool.slab_new()
	_ = s
}
