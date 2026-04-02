package test_allocator_detection

import "core:fmt"
import "core:mem"

// Test case 1: Should NOT trigger C001 - has allocator argument
// This should be skipped because it uses context.allocator
test_with_context_allocator :: proc() {
    data := make([]int, 10, context.allocator)  // Should NOT trigger - has allocator
    // No defer needed - uses custom allocator
}

// Test case 2: Should NOT trigger C001 - has temp_allocator
// This should be skipped because it uses temp_allocator
test_with_temp_allocator :: proc() {
    buffer := make([]byte, 1024, temp_allocator)  // Should NOT trigger - has allocator
    // No defer needed - uses custom allocator
}

// Test case 3: SHOULD trigger C001 - no allocator argument
// This should be flagged because it uses default allocator
test_without_allocator :: proc() {
    data := make([]int, 10)  // SHOULD trigger C001 - default allocator, no defer
    // Missing defer free!
}

// Test case 4: Should NOT trigger C001 - comment mentions allocator
// This should NOT be skipped just because "allocator" appears in comment
test_with_allocator_comment :: proc() {
    data := make([]int, 10)  // This allocator is default
    defer free(data)  // Properly handled
}

// Test case 5: Should NOT trigger C001 - variable named allocator
// This should NOT be skipped just because there's a variable named allocator
test_with_allocator_variable :: proc() {
    allocator := "some_value"  // Variable named allocator
    data := make([]int, 10)     // Should trigger if no defer
    defer free(data)  // Properly handled
}

// Test case 6: SHOULD trigger C001 - slice with capacity but no allocator
// make([]T, size, capacity) should trigger if no defer
test_slice_with_capacity :: proc() {
    data := make([]int, 10, 100)  // SHOULD trigger - no allocator arg, no defer
    // Missing defer free!
}

main :: proc() {
    fmt.println("Test file for allocator detection")
    test_with_context_allocator()
    test_with_temp_allocator()
    test_without_allocator()
    test_with_allocator_comment()
    test_with_allocator_variable()
    test_slice_with_capacity()
}
