package main

import "core:fmt"
import "core:os"

// Test case: Comprehensive edge cases for C002 double-free detection
// This tests both manual and SCM implementations for identical behavior

main :: proc() {
    // Case 1: Simple double-free (should trigger C002)
    simple_case()
    
    // Case 2: Nested scopes with double-free (should trigger C002)
    nested_scope_case()
    
    // Case 3: Complex variable names (should trigger C002)
    complex_names_case()
    
    // Case 4: Multiple allocations, one double-free (should trigger C002)
    multiple_allocations_case()
    
    // Case 5: Reassignment before double-free (edge case)
    reassignment_case()
    
    // Case 6: Underscore variable names (should trigger C002)
    underscore_case()
    
    fmt.println("All test cases completed")
}

simple_case :: proc() {
    buf := make([]u8, 1024)
    defer free(buf)   // First free - OK
    defer free(buf)   // Second free - C002 VIOLATION
}

nested_scope_case :: proc() {
    outer := make([]int, 100)
    defer free(outer) // First free - OK
    
    if true {
        // Same variable in nested scope
        defer free(outer) // Second free - C002 VIOLATION
    }
}

complex_names_case :: proc() {
    very_long_variable_name123 := make([]string, 50)
    defer free(very_long_variable_name123) // First free - OK
    defer free(very_long_variable_name123) // Second free - C002 VIOLATION
}

multiple_allocations_case :: proc() {
    // Multiple allocations, but only one has double-free
    buf1 := make([]u8, 100)
    defer free(buf1) // OK - only freed once
    
    buf2 := make([]u8, 200)
    defer free(buf2) // First free - OK
    defer free(buf2) // Second free - C002 VIOLATION
    
    buf3 := make([]u8, 300)
    defer free(buf3) // OK - only freed once
}

reassignment_case :: proc() {
    ptr := make([]u8, 100)
    defer free(ptr) // First free - OK
    
    // Reassign (this is a different allocation)
    ptr = make([]u8, 200)
    defer free(ptr) // This should be OK - different allocation
    defer free(ptr) // Second free of same allocation - C002 VIOLATION
}

underscore_case :: proc() {
    _test_var := make([]u8, 100)
    defer free(_test_var) // First free - OK
    defer free(_test_var) // Second free - C002 VIOLATION
    
    __another_var := make([]u8, 100)
    defer free(__another_var) // First free - OK
    defer free(__another_var) // Second free - C002 VIOLATION
}

// Test case: Mixed make/new allocations
mixed_allocations :: proc() {
    slice1 := make([]int, 10)
    defer free(slice1) // First free - OK
    defer free(slice1) // Second free - C002 VIOLATION
    
    // Note: This would need actual pointer allocation to test 'new'
    // For now, we focus on make() which is the primary case
}

// Test case: Conditional double-free (only one path should trigger)
conditional_case :: proc() {
    buf := make([]u8, 100)
    
    if true {
        defer free(buf) // First free - OK
    }
    
    if true {
        defer free(buf) // Second free - C002 VIOLATION
    }
}

// Test case: Function parameter double-free
parameter_case :: proc() {
    buf := make([]u8, 100)
    defer free(buf) // First free - OK
    
    // Pass to function that also frees
    free_in_function(buf) // This should be OK - not a defer
    
    defer free(buf) // Second defer free - C002 VIOLATION
}

free_in_function :: proc(ptr: []u8) {
    // This is a direct free, not defer, so it doesn't count for C002
    // But it's still a double-free at runtime
}

// Test case: Loop with potential double-free
loop_case :: proc() {
    for i in 0..2 {
        buf := make([]u8, 100)
        defer free(buf) // Each iteration has its own scope
        // This should be OK - different instances
    }
}

// Test case: Proc literal with double-free
proc_literal_case :: proc() {
    buf := make([]u8, 100)
    
    proc_literal := proc() {
        // This should trigger a context reset in C002
        // So this free should not see the outer allocation
        defer free(buf) // C002 VIOLATION (if context not reset)
    }
    
    defer free(buf) // First free in outer scope - OK
    proc_literal() // This calls the proc literal
    defer free(buf) // Second free in outer scope - C002 VIOLATION
}