// Test case for the specific problematic pattern mentioned in the issue
package main

main :: proc() {
    // This was the case that was supposedly failing
    ptr := new(Data)
    defer delete(ptr)  // Should be recognized as proper cleanup
    
    // Additional test cases
    data := make([]int, 100)
    defer free(data)  // Should also be recognized
}

// Test without package declaration (like the original failing case)
proc test_without_package() {
    buf := new(int)
    defer delete(buf)  // Should work even without package context
}

Data :: struct {
    value: int,
}