// C002 Edge Case: Scope and shadowing issues
// Tests pointer usage across different scopes and shadowing scenarios

package main

import "core:fmt"

main :: proc() {
    // Case 1: Shadowing in inner scope
    ptr := make([]int, 10)
    defer free(ptr)  // Free outer ptr
    
    {
        ptr := make([]int, 20)  // Shadow outer ptr
        defer free(ptr)  // Free inner ptr - correct
    }
    
    // Case 2: Pointer passed to function that reassigns
    test_reassign_in_function()
    
    // Case 3: Pointer returned from function
    result := get_pointer()
    defer free(result)  // Should this be flagged? We don't know what get_pointer returns
}

proc test_reassign_in_function() {
    original := make([]int, 15)
    
    // Pass to function that might reassign
    modify_pointer(&original)
    
    defer free(original)  // Is this the same pointer that was allocated?
}

proc modify_pointer(ptr: ^[]int) {
    // This function could reassign the pointer
    if true {
        *ptr = make([]int, 25)  // Reassignment through pointer
    }
}

proc get_pointer() -> []int {
    if true {
        return make([]int, 30)
    } else {
        return make([]int, 40)
    }
}

// Case 4: Closure capturing reassigned pointer
proc test_closure_capture() {
    data := make([]int, 5)
    
    cleanup := proc() {
        defer free(data)  // Captured by closure
    }
    
    data = make([]int, 15)  // Reassignment after closure creation
    cleanup()  // Which allocation gets freed?
}