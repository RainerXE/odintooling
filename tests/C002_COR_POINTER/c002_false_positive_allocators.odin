// Test system allocator patterns that should NOT trigger C002
package main

import "core:runtime"

main :: proc() {
    // Pattern 1: Temporary allocator
    temp_data := make([]int, 100, runtime.temp_allocator)
    defer delete(temp_data)  // Should NOT trigger C002
    
    // Pattern 2: Context allocator simulation
    // Note: context.allocator is a common pattern in Odin core
    ctx_data := make([]int, 200)
    // Simulate context allocator pattern
    defer free(ctx_data)  // Should NOT trigger C002 in system contexts
    
    // Pattern 3: Custom allocator parameter
    custom_alloc_data := make([]int, 150)
    defer free(custom_alloc_data)  // Should NOT trigger C002
    
    // Use the allocations
    if len(temp_data) > 0 {
        temp_data[0] = 1
    }
    if len(ctx_data) > 0 {
        ctx_data[0] = 2
    }
    if len(custom_alloc_data) > 0 {
        custom_alloc_data[0] = 3
    }
}