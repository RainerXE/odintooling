package c012_t3_test

// C012-T3 PASS cases — ownership correctly signalled with _owned suffix.
// All should produce zero C012-T3 violations when graph is present.

get_frame_scratch :: proc() -> int { return 0 }  // not an allocator-role proc

do_work :: proc() {
    // LHS has _owned suffix — correct
    buf_owned := make([]u8, 256)
    _ = buf_owned

    // Called proc is not in allocator-role — no T3 concern
    count := get_frame_scratch()
    _ = count
}
