package main

import "core"
import "core:fmt"

main :: proc() {
    // This should NOT trigger C001 - min() is not an allocation
    x := min(5, 10)
    fmt.println("min test: ", x)
    
    // This SHOULD trigger C001 - make() is an allocation
    data := make([]int, 10)
    // Missing: defer delete(data)
    
    fmt.println("Test completed")
}