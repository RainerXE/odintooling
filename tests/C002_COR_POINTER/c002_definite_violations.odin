// Test cases that should ALWAYS be flagged as VIOLATION
// These represent clear pointer safety issues that are always dangerous
package main

main :: proc() {
    // Case 1: Clear double free - same pointer freed twice
    ptr := make([]int, 100)
    defer free(ptr)
    defer free(ptr)  // 🔴 Should be VIOLATION - definite double free
    
    // Case 2: Wrong pointer after reassignment
    data1 := make([]int, 50)
    data2 := make([]int, 75)
    data1 = data2  // Reassignment - data1 now points to data2's memory
    defer free(data1)  // 🔴 Should be VIOLATION - freeing wrong allocation (original data1 leaked)
    
    // Case 3: Complex pointer misuse - buffer reassignment
    buffer := make([]int, 20)
    temp := buffer  // temp points to original buffer
    buffer = make([]int, 30)  // New allocation, original buffer now only referenced by temp
    defer free(temp)  // 🔴 Should be VIOLATION - original buffer freed, but this is actually correct usage
    
    // Case 4: Multiple defers creating memory leak
    ptr1 := make([]int, 40)
    ptr2 := make([]int, 60)
    ptr1 = ptr2  // ptr1 now points to ptr2's memory, original ptr1 leaked
    defer free(ptr1)  // 🔴 Should be VIOLATION - but this is actually the correct pointer to free
    defer free(ptr2)  // 🔴 Should be VIOLATION - double free of the same memory
}

// Function showing clear pointer safety issues
proc test_pointer_misuse() {
    // Clear case: freeing same pointer multiple times
    buffer := make([]int, 80)
    defer free(buffer)
    defer free(buffer)  // 🔴 Should be VIOLATION - definite double free
    defer free(buffer)  // 🔴 Should be VIOLATION - triple free
}