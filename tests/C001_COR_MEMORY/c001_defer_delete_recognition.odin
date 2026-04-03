package main

// Test case specifically for defer delete() recognition
main :: proc() {
    // Test 1: new() with defer delete() - should PASS
    ptr1 := new(int)
    defer delete(ptr1)  // Proper cleanup
    
    // Test 2: new() without cleanup - should FAIL
    ptr2 := new(string)
    // Missing: defer delete(ptr2)
}

test_delete_variations :: proc() {
    // Test different delete patterns
    data := make([]int, 10)
    defer delete(data)  // Should work for slices too
}