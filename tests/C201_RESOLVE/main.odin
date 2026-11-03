package app

import "lib"
import "core:os"
import "core:mem"
import "core:io"
import fp "lib"

// C201 reports a bare call whose error result is discarded. Each call below is marked with what is expected.
main :: proc() {
	lib.risky()                // reported: lib.risky returns Error
	lib.quiet()                // quiet: returns int
	lib.pair()                 // reported: returns (int, Error)
	lib.alloc_only()           // quiet: an allocator error is optional
	lib.risky_group()          // reported: every member returns Error
	lib.mixed_group()          // quiet: one member does not
	fp.risky()                 // reported: through the alias fp
	x, _ := lib.pair()         // quiet: not a bare call
	_ = x
	mem.free(nil)              // quiet: Allocator_Error
	io.write_string(nil, "x")  // quiet: stream output is discarded as a matter of course
	os.set_env("A", "b")       // reported: core:os, needs an Odin installation
}
