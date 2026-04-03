// C002 Edge Case: Pointer reassignment before free
// Tests the case where a pointer is reassigned before being freed

package main

import "core:fmt"

main :: proc() {
    // Case 1: Simple reassignment
    ptr1 := make([]int, 10)
    ptr2 := make([]int, 20)
    ptr1 = ptr2  // ptr1 now points to same memory as ptr2
    defer free(ptr1)  // Should this trigger C002? Original ptr1 allocation is lost
    
    // Case 2: Reassignment in loop
    for i in 0..<5 {
        temp_ptr := make([]int, i)
        if i > 2 {
            temp_ptr = make([]int, 100)  // Reassignment
        }
        defer free(temp_ptr)
    }
    
    // Case 3: Multiple reassignments
    data := make([]int, 50)
    data = make([]int, 75)  // First reassignment
    data = make([]int, 100) // Second reassignment
    defer free(data)  // Which allocation should this free?
}

// Test function with parameter reassignment
proc test_param_reassignment() {
    original := make([]int, 15)
    defer free(original)
    
    // Reassign parameter (should this be flagged?)
    original = make([]int, 25)
    // No defer free for the new allocation - potential memory leak
}