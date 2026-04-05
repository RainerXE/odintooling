// Test cases that should NOT be flagged at all
// These represent definitely safe patterns
package main

some_condition :: proc() -> bool {
    return true
}

main :: proc() {
    // Case 1: Conditional defer (already handled by current implementation)
    ptr := make([]int, 100)
    defer if some_condition() { free(ptr) }  // ✅ Should NOT flag - conditional defer
    
    // Case 2: Well-known safe function patterns (hypothetical safe functions)
    // safe_data := system_allocate_safely()  // Would need actual safe function
    // defer free(safe_data)  // ✅ Should NOT flag - known safe function
    
    // Case 3: Legacy patterns in specific contexts
    // legacy_ptr := legacy_allocate()  // Would need actual legacy function
    // defer free(legacy_ptr)  // ✅ Should NOT flag - legacy context
    
    // Case 4: Simple single allocation with single defer (should not trigger C002)
    simple_ptr := make([]int, 50)
    defer free(simple_ptr)  // ✅ Should NOT flag - simple correct pattern
    
    // Case 5: Different variables, no reassignment
    data1 := make([]int, 30)
    data2 := make([]int, 40)
    defer free(data1)  // ✅ Should NOT flag - different variables
    defer free(data2)  // ✅ Should NOT flag - different variables
}

// Function with safe memory patterns
proc safe_memory_usage() {
    // Simple correct usage
    buffer := make([]int, 100)
    defer free(buffer)  // ✅ Should NOT flag - simple correct pattern
    
    // Multiple allocations, each freed once
    arr1 := make([]int, 20)
    arr2 := make([]int, 30)
    defer free(arr1)  // ✅ Should NOT flag
    defer free(arr2)  // ✅ Should NOT flag
}