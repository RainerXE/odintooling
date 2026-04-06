package main

main :: proc() {
    ptr := make([]int, 100)
    defer free(ptr)
    defer free(ptr)  // Double free - should be detected
}