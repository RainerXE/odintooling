// Test conditional defer patterns that should NOT trigger C002
package main

some_condition :: proc() -> bool {
    return true
}

main :: proc() {
    // Pattern 1: Conditional defer with error handling
    ptr := make([]int, 100)
    defer if some_condition() { free(ptr) }  // Should NOT trigger C002
    
    // Pattern 2: Conditional defer with allocator check
    costs := make([]int, 50)
    threshold := 25
    defer if len(costs) > threshold { delete(costs) }  // Should NOT trigger C002
    
    // Pattern 3: Error-based conditional defer
    data := make([]int, 75)
    err := false
    defer if err { free(data) }  // Should NOT trigger C002
    
    // Use the allocations to prevent optimization
    if len(ptr) > 0 {
        ptr[0] = 42
    }
    if len(costs) > 0 {
        costs[0] = 100
    }
    if len(data) > 0 {
        data[0] = 200
    }
}