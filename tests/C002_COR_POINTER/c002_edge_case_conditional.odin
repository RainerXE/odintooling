// C002 Edge Case: Conditional free patterns
// Tests defer free in conditional branches and complex control flow

package main

import "core:fmt"

main :: proc() {
    // Case 1: Conditional allocation with unconditional free
    data := make([]int, 50)
    
    if true {
        data = make([]int, 100)  // Conditional reassignment
    }
    
    defer free(data)  // Should this trigger C002? Depends on path taken
    
    // Case 2: Different allocations in different branches
    result := make([]int, 10)
    
    if true {
        result = make([]int, 20)
    } else {
        result = make([]int, 30)
    }
    
    defer free(result)  // Which allocation gets freed?
    
    // Case 3: Early return with defer
    test_early_return()
}

proc test_early_return() {
    ptr := make([]int, 15)
    
    if true {
        defer free(ptr)
        return
    }
    
    // This code is unreachable, but shows the pattern
    ptr = make([]int, 25)
    defer free(ptr)  // Should this be flagged?
}

// Case 4: Complex boolean conditions
proc test_complex_conditions() {
    a := make([]int, 10)
    b := make([]int, 20)
    
    target := a
    if true && false || true {
        target = b
    }
    
    defer free(target)  // Complex control flow - hard to determine correct pointer
}