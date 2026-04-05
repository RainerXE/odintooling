// Test complex expressions that should NOT trigger C002
package main

main :: proc() {
    // Pattern 1: Pointer arithmetic (Odin-style)
    data := make([]int, 100)
    slice := data[10..<50]  // Complex slicing
    defer free(data)  // Should NOT trigger C002
    
    // Pattern 2: Nested memory operations
    outer := make([][]int, 10)
    for i in 0..<len(outer) {
        outer[i] = make([]int, 20)
        defer free(outer[i])  // Should NOT trigger C002
    }
    
    // Pattern 3: Array of pointers with complex indexing
    ptr_array := make([dynamic]^int, 5)
    for i in 0..<len(ptr_array) {
        ptr_array[i] = new(int)
        defer delete(ptr_array[i])  // Should NOT trigger C002
    }
    
    // Pattern 4: Struct with pointer fields
    Data_Holder :: struct {
        ptr1: ^int,
        ptr2: ^int,
    }
    
    holder := Data_Holder{}
    holder.ptr1 = new(int)
    holder.ptr2 = new(int)
    defer delete(holder.ptr1)  // Should NOT trigger C002
    defer delete(holder.ptr2)  // Should NOT trigger C002
    
    // Use some of the allocations
    if len(data) > 0 {
        data[0] = 42
    }
    if len(slice) > 0 {
        slice[0] = 100
    }
}