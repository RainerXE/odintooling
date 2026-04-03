// Test case for C001: Proper allocation with defer free
// This should NOT trigger C001 diagnostic

package main

import "core:fmt"

main :: proc() {
    // ✅ CORRECT: Allocation with proper defer free
    data := make([]int, 100)
    defer free(data)  // Proper cleanup
    
    // Use the allocated data
    for i := 0; i < len(data); i++ {
        data[i] = i * 2
    }
    
    fmt.println("Data processed correctly")
}

// Another example with new allocation
proc test() {
    buf := new(int)
    defer delete(buf)  // Proper cleanup
    *buf = 42
}
