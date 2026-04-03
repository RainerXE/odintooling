// Test case for C002: Defer free on wrong pointer
// This should trigger C002 diagnostic

package main

import "core:fmt"

main :: proc() {
    // Allocate first pointer
    data1 := make([]int, 100)
    defer free(data1)  // ✅ Correct
    
    // Allocate second pointer
    data2 := make([]int, 200)
    
    // ❌ VIOLATION: Freeing wrong pointer
    // Should free data2 but freeing data1 again
    defer free(data1)  // C002 should trigger here
    
    // Use both buffers
    for i := 0; i < len(data1); i++ {
        data1[i] = i
    }
    for i := 0; i < len(data2); i++ {
        data2[i] = i * 2
    }
}

// Another example with reassignment
proc test_reassignment() {
    ptr1 := make([]int, 50)
    ptr2 := make([]int, 75)
    
    // Reassign ptr1 to ptr2
    ptr1 = ptr2
    
    // ❌ VIOLATION: Freeing original ptr1 (now lost)
    // Should free ptr2 but ptr1 was reassigned
    defer free(ptr1)  // C002 should trigger here
}
