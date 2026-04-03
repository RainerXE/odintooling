package main

import "core"
import "core:fmt"

main :: proc() {
    // This SHOULD trigger C001 - allocation without defer free
    data1 := make([]int, 10)
    
    // This SHOULD be suppressed - has suppression comment on same line
    data2 := make([]int, 10)  // odin-lint:ignore C001 intentional ownership transfer
    
    // This SHOULD be suppressed - has suppression comment on previous line
    // odin-lint:ignore C001 caller takes ownership
    data3 := make([]int, 10)
    
    // This SHOULD trigger C001 - no suppression comment
    data4 := new(Data)
    
    fmt.println("Suppression test completed")
}

Data :: struct {}