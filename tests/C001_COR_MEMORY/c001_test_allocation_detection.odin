package main

import "core:fmt"

// Test case to verify allocation detection
main :: proc() {
    // Test 1: make() allocation - should trigger C001
    data1 := make([]int, 100)
    // Missing: defer free(data1)
    
    // Test 2: new() allocation - should trigger C001  
    ptr1 := new(int)
    // Missing: defer delete(ptr1)
    
    fmt.println("Testing allocation detection")
}

// Test with proper cleanup - should NOT trigger C001
test_proper_cleanup :: proc() {
    // This should PASS
    data2 := make([]int, 50)
    defer free(data2)
    
    ptr2 := new(int)
    defer delete(ptr2)
}

// Test mixed scenarios
test_mixed :: proc() {
    // Should trigger C001 for data3
    data3 := make([]string, 20)
    // Missing: defer free(data3)
    
    // This is OK
    ptr3 := new(int)
    defer delete(ptr3)
}