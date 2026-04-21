package c012_t3_test

// C012-T3 FAIL cases — allocator factory return not labelled _owned.
// These require the graph DB with get_scratch tagged as memory_role='allocator'.
// See scripts/run_c012_tests.sh for how the graph is built before running.

get_scratch :: proc() -> int { return 0 }  // tagged allocator in test graph

do_work :: proc() {
    // get_scratch is allocator-role in graph but LHS has no _owned suffix
    result := get_scratch()
    _ = result
}
