// C002 Comprehensive Test: Double-Free Patterns
// This file tests various double-free scenarios that C002 should detect

package main

import "core:fmt"

// Test Case 1: Basic double-free (should trigger C002)
proc test_basic_double_free() {
    data := make([]int, 100)
    defer free(data)  // First free
    defer free(data)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 2: Double-free with := declaration (should trigger C002)
proc test_declaration_double_free() {
    buf := make([]u8, 200)
    defer free(buf)  // First free
    defer free(buf)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 3: Double-free in conditional (should trigger C002)
proc test_conditional_double_free() {
    buffer := make([]int, 50)
    if true {
        defer free(buffer)  // First free
    }
    defer free(buffer)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 4: Double-free in loop (should trigger C002)
proc test_loop_double_free() {
    for i in 0..<5 {
        ptr := make([]int, i)
        defer free(ptr)  // First free
        defer free(ptr)  // ❌ C002: Second free - DOUBLE-FREE
    }
}

// Test Case 5: Double-free with different variables (should NOT trigger C002)
proc test_different_variables() {
    buf1 := make([]int, 100)
    defer free(buf1)  // First variable
    
    buf2 := make([]int, 200)
    defer free(buf2)  // ✅ Different variable - OK
}

// Test Case 6: Single free (should NOT trigger C002)
proc test_single_free() {
    data := make([]int, 100)
    defer free(data)  // ✅ Single free - OK
}

// Test Case 7: Double-free with delete (should trigger C002)
proc test_delete_double_free() {
    ptr := make([]int, 50)
    defer delete(ptr)  // First free
    defer delete(ptr)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 8: Mixed free and delete (should trigger C002)
proc test_mixed_free_delete() {
    buffer := make([]int, 75)
    defer free(buffer)   // First free
    defer delete(buffer) // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 9: Double-free in nested scopes (should trigger C002)
proc test_nested_scope_double_free() {
    outer := make([]int, 100)
    defer free(outer)
    
    {
        inner := make([]int, 50)
        defer free(inner)  // First free
        defer free(inner)  // ❌ C002: Second free - DOUBLE-FREE
    }
}

// Test Case 10: Double-free with reassignment (contextual, may not trigger C002)
proc test_reassignment_pattern() {
    ptr1 := make([]int, 50)
    ptr2 := make([]int, 75)
    ptr1 = ptr2  // Reassignment
    defer free(ptr1)  // Contextual: pointer was reassigned
}

main :: proc() {
    fmt.println("C002 Comprehensive Test Suite")
    fmt.println("============================")
    fmt.println("This file contains test cases for double-free detection.")
    fmt.println("Expected C002 violations: 8")
    fmt.println("Run with: ./odin-lint tests/C002_COR_POINTER/c002_double_free_comprehensive.odin")
}