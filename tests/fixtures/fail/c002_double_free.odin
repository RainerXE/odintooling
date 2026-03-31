// Test case for C002: potential double-free risk

main :: proc() {
    data := make([]int, 100)
    defer free(data)  // First free
    
    // Some code...
    for i in 0..<len(data) {
        data[i] = i * 2
    }
    
    // Potential double-free if data is modified
    defer free(data)  // Second free - potential issue
}