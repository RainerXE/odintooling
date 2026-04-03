package test_defer_extraction

import "core:fmt"
import "core:mem"

// Test case 1: Simple defer free
test_simple_defer :: proc() {
    data := new(int)
    defer free(data)  // Should extract "data"
}

// Test case 2: Defer delete
test_defer_delete :: proc() {
    arr := make([]int, 10)
    defer delete(arr)  // Should extract "arr"
}

// Test case 3: Multiple defers
test_multiple_defers :: proc() {
    a := new(string)
    b := make([]float32, 5)
    defer free(a)     // Should extract "a"
    defer delete(b)   // Should extract "b"
}

// Test case 4: Nested scope
test_nested_scope :: proc() {
    outer := new(Node)
    defer free(outer)  // Should extract "outer"
    
    if true {
        inner := make([]byte, 100)
        defer delete(inner)  // Should extract "inner"
    }
}

// Test case 5: Complex expression (should handle gracefully)
test_complex :: proc() {
    // This might not be extracted perfectly, but shouldn't crash
    ptr := new(int)
    defer free(ptr)  // Should extract "ptr"
}

Node :: struct {}

main :: proc() {
    fmt.println("Test file for defer variable extraction")
    // Run all test cases to ensure they compile
    test_simple_defer()
    test_defer_delete()
    test_multiple_defers()
    test_nested_scope()
    test_complex()
}
