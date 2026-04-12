// C002 Comprehensive Test: Double-Free Patterns
// This file tests various double-free scenarios that C002 should detect

package main

import "core:fmt"

// Test Case 1: Basic double-free (should trigger C002)
test_basic_double_free :: proc() {
    data := make([]int, 100)
    defer free(data)  // First free
    defer free(data)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 2: Double-free with := declaration (should trigger C002)
test_declaration_double_free :: proc() {
    buf := make([]u8, 200)
    defer free(buf)  // First free
    defer free(buf)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 3: Cross-block double-free (known SCM limitation — not detected)
// The SCM scopes by innermost block to avoid false positives in if-branches.
// Two defers in DIFFERENT blocks for the same name are not flagged.
test_conditional_double_free :: proc() {
    buffer := make([]int, 50)
    {
        defer free(buffer)  // First free — inner block
    }
    defer free(buffer)  // Would be a double-free, but cross-block — not detected by SCM
}

// Test Case 4: Double-free in loop (should trigger C002)
test_loop_double_free :: proc() {
    for _ in 0..<5 {
        ptr := make([]int, 10)
        defer free(ptr)  // First free
        defer free(ptr)  // ❌ C002: Second free - DOUBLE-FREE
    }
}

// Test Case 5: Different variables — should NOT trigger C002
test_different_variables :: proc() {
    buf1 := make([]int, 100)
    defer free(buf1)  // ✅ Different variable - OK

    buf2 := make([]int, 200)
    defer free(buf2)  // ✅ Different variable - OK
}

// Test Case 6: Single free — should NOT trigger C002
test_single_free :: proc() {
    data := make([]int, 100)
    defer free(data)  // ✅ Single free - OK
}

// Test Case 7: Double-free with delete (should trigger C002)
test_delete_double_free :: proc() {
    ptr := make([]int, 50)
    defer delete(ptr)  // First free
    defer delete(ptr)  // ❌ C002: Second free - DOUBLE-FREE
}

// Test Case 8: Double-free in nested scopes (should trigger C002)
test_nested_scope_double_free :: proc() {
    outer := make([]int, 100)
    defer free(outer)

    {
        inner := make([]int, 50)
        defer free(inner)  // First free
        defer free(inner)  // ❌ C002: Second free - DOUBLE-FREE
    }
}

main :: proc() {
    fmt.println("C002 Comprehensive Test Suite")
    fmt.println("Expected C002 violations: 5 (cases 1, 2, 4, 7, 8)")
    fmt.println("Case 3 is a cross-block pattern — known SCM limitation, not detected")
}
