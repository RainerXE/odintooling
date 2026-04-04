// C002 Test: Nested scopes with allocations
package main

main :: proc() {
    // Outer scope allocation
    outer := make([]int, 100)
    defer free(outer)
    
    // Inner scope with its own allocation
    if true {
        inner := make([]int, 50)
        defer free(inner)  // Should not conflict with outer
        
        // Use the allocations
        outer[0] = 1
        inner[0] = 2
    }
    
    // Outer scope continues
    for i in 0..<len(outer) {
        outer[i] = i
    }
}
