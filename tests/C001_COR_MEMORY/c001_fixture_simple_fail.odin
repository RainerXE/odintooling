// Test case for C001: allocation without defer free
package main

main :: proc() {
    // This should trigger C001 when implemented
    data := make([]int, 100)  // Allocation without defer free
    
    // Process data...
    for i in 0..<len(data) {
        data[i] = i * 2
    }
    
    // Missing: defer delete(data)
}