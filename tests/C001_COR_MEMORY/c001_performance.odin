package main

import "core"
import "core:fmt"

// Test performance-critical code detection
main :: proc() {
    fmt.println("Testing performance-critical detection...")
    
    // Test case 1: Hot path with comment marker
    // // PERF: This is a hot path, allocations are intentional
    hot_path_data := new(Data)
    // No defer free - but should NOT trigger C001 due to PERF comment
    
    // Test case 2: Regular code (should trigger C001)
    regular_data := new(Data)
    // Missing defer free(regular_data)
    
    fmt.println("Performance test completed")
}

Data :: struct {}
