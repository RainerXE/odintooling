// Simple C002 Test: Double-Free in Single Procedure
package main

main :: proc() {
    // This should trigger C002: double-free in same scope
    data := make([]int, 100)
    defer free(data)  // First free
    defer free(data)  // ❌ C002: Second free - DOUBLE-FREE
}