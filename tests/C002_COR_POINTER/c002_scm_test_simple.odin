package main

// Simple test for SCM implementation
main :: proc() {
    // This should trigger exactly ONE C002 violation
    buf := make([]u8, 100)
    defer free(buf) // First free - OK
    defer free(buf) // Second free - C002 VIOLATION
}