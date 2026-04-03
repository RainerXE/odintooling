package main

import "core"
import "core:fmt"

// Test allocator detection improvements
main :: proc() {
    fmt.println("Testing allocator detection...")
    
    // Test case 1: Allocator in middle parameters
    alloc := context.allocator
    elements := make([dynamic]Element, 1024, 1024, alloc)
    
    // Test case 2: chan.create_buffered with allocator
    // channel, err := chan.create_buffered(100, context.allocator)
    
    // Test case 3: Regular make without allocator (should trigger C001)
    regular_slice := make([]int, 10)
    // Missing defer delete(regular_slice)
    
    fmt.println("Allocator test completed")
}

Element :: struct {}
context :: struct {
    allocator: ^Allocator
}

Allocator :: struct {}
