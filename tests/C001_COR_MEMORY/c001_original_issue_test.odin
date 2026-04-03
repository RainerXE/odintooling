package main

// Reproduce the original issue: new() with defer delete() should be recognized
main :: proc() {
    // Original problematic case - this should PASS (no C001 violation)
    ptr := new(Data)
    defer delete(ptr)  // This should be recognized as proper cleanup
    
    // Use the pointer
    ptr.field = 42
}

// Another case that was failing
proc test_case() {
    buf := new(int)
    defer delete(buf)  // This should also be recognized
    *buf = 100
}

Data :: struct {
    field: int,
}