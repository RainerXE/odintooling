// This file contains intentional Odin errors for testing
// Expected errors:
// 1. Undeclared identifier
// 2. Type mismatch
// 3. Syntax error (unclosed string)

package main

import "core:fmt"

main :: proc() {
    // Error 1: Undeclared identifier
    fmt.println(undefined_variable)
    
    // Error 2: Type mismatch
    x: int = "not an integer"
    
    // Error 3: Syntax error (unclosed string)
    fmt.println("This string is not closed)
}
