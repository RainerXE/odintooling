package main

main :: proc() {
    ptr := make([]int, 100)
    defer free(ptr)
    defer free(ptr)  // This should be detected as double free
    defer free(ptr)  // This should also be detected
}