package main

import "core"
import "core:fmt"

main :: proc() {
    // Test various functions that should NOT be flagged
    x := min(5, 10)      // Should NOT trigger
    y := max(5, 10)      // Should NOT trigger
    z := min_max(5, 10)  // Should NOT trigger (custom function)
    
    // Test allocations that SHOULD be flagged
    data1 := make([]int, 10)        // Should trigger
    data2 := new(Data)              // Should trigger
    
    fmt.println("Edge cases test completed")
}

Data :: struct {}

min_max :: proc(a, b: int) -> int {
    if a < b {
        return a
    }
    return b
}