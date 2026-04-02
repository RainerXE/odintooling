package main

import "core"
import "core:fmt"

main :: proc() {
    // This should trigger C001 - allocation without defer free
    data := new(Data)
    // Missing: defer free(data)
    
    fmt.println("Simple test")
}

Data :: struct {}
