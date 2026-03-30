package main

import "core:fmt"

main :: proc() {
    fmt.println("Hello, World!")
    // This should trigger our test diagnostic
    x := 42
}