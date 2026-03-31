// Test case for C002: Proper defer free usage
// This should NOT trigger C002 diagnostic

package main

import "core:fmt"

main :: proc() {
    // ✅ CORRECT: Each allocation has its own defer free
    data1 := make([]int, 100)
    defer free(data1)
    
    data2 := make([]int, 200)
    defer free(data2)  // Correct: freeing the right pointer
    
    // Use both buffers
    for i := 0; i < len(data1); i++ {
        data1[i] = i
    }
    for i := 0; i < len(data2); i++ {
        data2[i] = i * 2
    }
}

// Another example with proper usage
proc test_proper_usage() {
    ptr1 := make([]int, 50)
    defer free(ptr1)  // ✅ Correct: freeing allocated pointer
    
    ptr2 := make([]int, 75)
    defer free(ptr2)  // ✅ Correct: each has its own defer
}
