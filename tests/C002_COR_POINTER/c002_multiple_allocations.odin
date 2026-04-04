// C002 Test: Multiple allocations in same scope
package main

main :: proc() {
    // Multiple allocations - all should be tracked separately
    ptr1 := make([]int, 100)
    ptr2 := make([]int, 200)
    ptr3 := make([]int, 300)
    
    defer free(ptr1)
    defer free(ptr2)
    defer free(ptr3)
    
    // Reassign one pointer (should trigger C002)
    ptr2 = make([]int, 250)  // Reassignment
    defer free(ptr2)  // Second free of ptr2 - should trigger violation
    
    // Use the allocations
    ptr1[0] = 1
    ptr3[0] = 3
}
