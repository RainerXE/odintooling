package main

import "core"
import "core:fmt"

main :: proc() {
    // 1. Built-in allocation functions (should be flagged)
    data1 := make([]int, 10)          // ❌ Should be flagged
    data2 := make([dynamic]int)       // ❌ Should be flagged
    data3 := make(map[string]int)      // ❌ Should be flagged
    data4 := make(chan int)           // ❌ Should be flagged
    data5 := new(Data)                // ❌ Should be flagged
    
    // 2. Slice literals (need to check if these allocate)
    slice1 := []int{1, 2, 3}          // ❓ Does this allocate?
    
    // 3. Dynamic arrays (need to check)
    dyn_array := [dynamic]int{1, 2, 3} // ❓ Does this allocate?
    
    // 4. Array literals (stack allocated - should NOT be flagged)
    array1 := [...]int{1, 2, 3}        // ✅ Should NOT be flagged (stack)
    
    // 5. String conversions (need to check)
    str1 := string([]byte{65, 66, 67}) // ❓ Does this allocate?
    bytes1 := []byte("hello")         // ❓ Does this allocate?
    
    // 6. Type conversions (need to check)
    conv1 := []int(array1)            // ❓ Does this allocate?
    
    // 7. Context allocator (should NOT be flagged - custom allocator)
    // ctx := context.new()            // Would need context import
    // buf := ctx.allocator.allocate(1024) // Custom allocator
    
    fmt.println("Allocation methods test completed")
}

Data :: struct {
    value: int
}