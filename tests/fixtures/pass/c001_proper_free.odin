// Test case for C001: proper allocation with defer free

main :: proc() {
    // This should pass C001
    data := make([]int, 100)
    defer delete(data)  // Proper cleanup
    
    // Process data...
    for i in 0..<len(data) {
        data[i] = i * 2
    }
}