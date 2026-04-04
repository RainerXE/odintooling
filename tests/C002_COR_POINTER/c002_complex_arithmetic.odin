// C002 Test: Complex pointer arithmetic patterns
package main

main :: proc() {
    // Test various pointer arithmetic patterns
    base := make([]int, 100)
    
    // Simple case - should not trigger
    defer free(base)
    
    // Complex expression (should trigger suspicious pattern)
    offset := 10
    ptr := base[offset:]  // Slice operation
    defer free(ptr)  // This might be suspicious
    
    // Pointer arithmetic in free call
    unsafe_ptr := unsafe_ptr_cast(base)
    // defer free(unsafe_ptr + 10)  // Would trigger pattern
    
    // Use the allocations
    base[0] = 1
}
