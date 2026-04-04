// C002 Test: delete() support
package main

main :: proc() {
    // Test delete() calls (should be tracked same as free)
    slice := make([]int, 100)
    
    // Single delete - should not trigger
    defer delete(slice)
    
    // Multiple deletes - should trigger C002
    defer delete(slice)  // Double delete
    
    // Use the slice
    slice[0] = 1
}
