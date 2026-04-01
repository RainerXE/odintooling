package main

import "core"
import "core:fmt"

// Test cases for C001 improvements
main :: proc() {
    fmt.println("Testing C001 improvements...")
    
    // Test case 1: Allocator in middle parameters (should NOT trigger C001)
    // doc.elements = make([dynamic]Element, 1024, 1024, allocator)
    
    // Test case 2: Slice allocation with defer delete (should NOT trigger C001)
    color_map := make([]int, 10)
    defer delete(color_map)
    
    // Test case 3: Performance-critical code (should NOT trigger C001)
    // // PERF: Hot path allocation
    // temp_data := new(Data)
    
    // Test case 4: Regular allocation without defer (SHOULD trigger C001)
    leaky_data := new(Data)
    // Missing defer free(leaky_data)
    
    fmt.println("Test cases completed")
}

Data :: struct {}
