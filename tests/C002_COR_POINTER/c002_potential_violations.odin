// Test cases that should be flagged as CONTEXTUAL (potential issues)
// These patterns may be safe in system code but dangerous in application code
package main

import "core:runtime"

main :: proc() {
    // Case 1: System allocator pattern - commonly safe in Odin core
    data := make([]int, 100, runtime.temp_allocator)
    defer delete(data)  // 🟡 Should be CONTEXTUAL - system allocator pattern
    
    // Case 2: String processing pattern - standard Odin idiom
    test_str := "hello:world:test"
    parts := bytes.split(test_str, ":")
    defer delete(parts)  // 🟡 Should be CONTEXTUAL - standard string pattern
    
    // Case 3: Temporary buffer in loop - common pattern
    for i in 0..<5 {
        temp := make([]int, i * 10)
        defer delete(temp)  // 🟡 Should be CONTEXTUAL - loop temporary
    }
    
    // Case 4: Context allocator usage
    ctx_data := make([]int, 200, context.allocator)
    defer delete(ctx_data)  // 🟡 Should be CONTEXTUAL - context allocator pattern
    
    // Case 5: Derived/temporary variable naming
    derived_buffer := make([]int, 50)
    defer delete(derived_buffer)  // 🟡 Should be CONTEXTUAL - "derived" naming pattern
}

// Function with system-level memory patterns
proc system_memory_usage() {
    // Pattern seen in Odin core libraries
    scratch := make([]byte, 1024, runtime.temp_allocator)
    defer delete(scratch)  // 🟡 Should be CONTEXTUAL - scratch buffer pattern
    
    // Another common system pattern
    work_buffer := make([]int, 256)
    defer delete(work_buffer)  // 🟡 Should be CONTEXTUAL - work buffer pattern
}