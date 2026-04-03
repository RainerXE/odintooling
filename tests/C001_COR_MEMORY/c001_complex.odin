package main

import "core:fmt"

main :: proc() {
    // Test case 1: Simple allocation without defer (should trigger)
    data1 := make([]int, 10)
    
    // Test case 2: Allocation with defer (should NOT trigger)
    data2 := make([]byte, 1024)
    defer free(data2)
    
    // Test case 3: new allocation without defer (should trigger)
    ptr := new(int)
    
    // Test case 4: new allocation with defer (should NOT trigger)
    ptr2 := new(float64)
    defer delete(ptr2)
    
    // Test case 5: Returned allocation (should NOT trigger due to escape hatch)
    result := make([]string, 5)
    return
    
    fmt.println("Test complete")
}