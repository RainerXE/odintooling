// C001 Make Slice Test - Tests make([]T) allocations without defer free
// Expected: Should trigger C001 violation

package c001_make_slice

main :: proc() {
    // VIOLATION: make without defer free
    slice := make([]int, 10)  // C001 should flag this
    
    // This should be flagged as potential memory leak
    buffer := make([]byte, 1024)  // C001 should flag this
}