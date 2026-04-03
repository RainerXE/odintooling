// C002 Edge Case: Complex expressions and pointer arithmetic
// Tests advanced patterns that might confuse the analyzer

package main

import "core:fmt"

main :: proc() {
    // Case 1: Pointer arithmetic (if supported by Odin)
    data := make([]int, 100)
    // pointer_math := &data[10]  // Pointer arithmetic - not typical in Odin
    defer free(data)
    
    // Case 2: Array slicing before free
    array := make([]int, 50)
    slice := array[10..<30]  // Create slice
    defer free(array)  // Free original array - should be OK
    
    // Case 3: Multiple defers in complex order
    test_multiple_defers()
    
    // Case 4: Pointer used in multiple contexts
    multi_context_test()
}

proc test_multiple_defers() {
    a := make([]int, 10)
    b := make([]int, 20)
    c := make([]int, 30)
    
    // Multiple reassignments with multiple defers
    target := a
    defer free(target)  // Should free 'a'
    
    target = b
    defer free(target)  // Should free 'b' - but 'a' is now leaked
    
    target = c
    defer free(target)  // Should free 'c' - but 'a' and 'b' are leaked
}

proc multi_context_test() {
    // Pointer used in struct
    Data :: struct {
        buffer: []int,
    }
    
    d := Data{buffer: make([]int, 25)}
    
    // Reassign struct field
    d.buffer = make([]int, 35)
    
    defer free(d.buffer)  // Which allocation? Original or reassigned?
    
    // Pointer in array
    pointers := [^[]int]{^make([]int, 40), ^make([]int, 45)}
    defer free(pointers[0]^)  // Complex expression
    defer free(pointers[1]^)
}

// Case 5: Defer in loop with conditional break
proc test_defer_loop() {
    for i in 0..<5 {
        ptr := make([]int, i * 10)
        
        if i == 3 {
            defer free(ptr)
            break  // Early exit - what happens to other allocations?
        }
        
        defer free(ptr)
    }
}