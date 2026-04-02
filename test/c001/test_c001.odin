package main

import "core:fmt"

main :: proc() {
    // This should trigger C001 - allocation without defer free
    data := make([]int, 10)
    
    // This should NOT trigger C001 - has defer free
    buffer := make([]byte, 1024)
    defer free(buffer)
    
    fmt.println("Test complete")
}