// C002 Explicit Violation Test
// This test case should definitely trigger C002

package main

import "core:fmt"

main :: proc() {
    // Clear case: freeing the same pointer twice
    ptr := make([]int, 50)
    defer free(ptr)  // First free - correct
    defer free(ptr)  // Second free - should trigger C002
    
    // Another clear case: wrong pointer in defer
    data1 := make([]int, 100)
    data2 := make([]int, 200)
    
    // Free data1 twice, never free data2
    defer free(data1)  // First free
    defer free(data1)  // Second free - should trigger C002
    
    // Use the data to prevent optimization
    for i in 0..<len(data1) {
        data1[i] = i
    }
    for i in 0..<len(data2) {
        data2[i] = i * 2
    }
}

// Function with obvious pointer misuse
proc test_double_free() {
    buffer := make([]int, 75)
    
    // Multiple defers on same pointer
    defer free(buffer)
    defer free(buffer)  // Clear violation
    defer free(buffer)  // Another violation
    
    // This should trigger multiple C002 diagnostics
}