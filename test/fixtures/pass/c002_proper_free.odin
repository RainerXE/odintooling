// Test case for C002: proper single free

main :: proc() {
    data := make([]int, 100)
    defer free(data)  // Single free - proper
    
    // Process data...
    for i in 0..<len(data) {
        data[i] = i * 2
    }
}