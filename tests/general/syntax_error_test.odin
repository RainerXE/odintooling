package main

import "core"
import "core:fmt"

main :: proc() {
    // This has a syntax error - missing closing brace
    if true {
        fmt.println("Hello")
    
    // This should not be reached
    fmt.println("World")
