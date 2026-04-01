package main

import "core"
import "core:fmt"

main :: proc() {
    fmt.println("Testing C001 improvements...")
    
    // Test case 1: Slice allocation with defer delete (should NOT trigger C001)
    color_map := make([]int, 10)
    defer delete(color_map)
    
    // Test case 2: Regular allocation without defer (SHOULD trigger C001)
    leaky_data := new(Data)
    // Missing defer free(leaky_data)
    
    fmt.println("Test cases completed")
}

Data :: struct {}
