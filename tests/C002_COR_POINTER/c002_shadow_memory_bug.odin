package main

// C002-Shadow-Memory-Bug: Test case based on real memory management bug
// This test case demonstrates a double-free pattern that occurred in the
// shadow mode implementation itself, showing how C002 can catch such issues.
//
// The bug: capture names were referencing tree-sitter's internal memory
// which got freed when ts_query_delete was called, creating dangling pointers.
// This is exactly the kind of memory management issue C002 should detect.

main :: proc() {
    // Simulate the problematic pattern: allocating and freeing the same resource twice
    buf := make([]u8, 1024)
    defer free(buf)  // First free - OK
    defer free(buf)  // Second free - C002 VIOLATION: double-free detected
    
    // This pattern is similar to what happened in the shadow mode:
    // 1. Allocate resource (tree-sitter query creates capture names)
    // 2. Free resource (ts_query_delete frees internal memory)
    // 3. Try to use freed resource (attempt to delete capture names)
    // 4. C002 catches the double-free attempt
}