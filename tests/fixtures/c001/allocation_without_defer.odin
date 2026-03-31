// Test case for C001: Allocation without matching defer free
// This should trigger C001 diagnostic

package main

import "core:fmt"

main :: proc() {
    // ❌ VIOLATION: Allocation without defer free
    data := make([]int, 100)  // C001 should trigger here
    
    // Use the allocated data
    for i := 0; i < len(data); i++ {
        data[i] = i * 2
    }
    
    fmt.println("Data processed")
    // Missing: defer free(data)
}

// Another example with new allocation
proc test() {
    buf := new(int)  // C001 should trigger here too
    *buf = 42
    // Missing: defer delete(buf)
}
