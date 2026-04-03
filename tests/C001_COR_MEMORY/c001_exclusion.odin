package main

import "core"
import "core:fmt"

main :: proc() {
    // Functions that should NOT be flagged (comprehensive test)
    x1 := min(5, 10)                  // ✅ Not flagged
    x2 := max(5, 10)                  // ✅ Not flagged  
    x3 := min_max(5, 10)              // ✅ Not flagged
    x4 := make_connection("db")       // ✅ Not flagged - starts with "make" but not "make("
    x5 := new_buffer(1024)            // ✅ Not flagged - starts with "new" but not "new("
    x6 := maker("type")               // ✅ Not flagged
    x7 := newbie("name")              // ✅ Not flagged
    x8 := make_something_else()       // ✅ Not flagged
    x9 := new_instance(Data{})         // ✅ Not flagged
    x10 := make_custom_thing(42)       // ✅ Not flagged
    
    // Functions that SHOULD be flagged (actual allocations)
    data1 := make([]int, 10)          // ❌ Should be flagged
    data2 := new(Data)                 // ❌ Should be flagged
    data3 := make([dynamic]int, 0)     // ❌ Should be flagged
    data4 := new(Data, "config")      // ❌ Should be flagged
    
    fmt.println("Comprehensive exclusion test completed")
}

Data :: struct {}

// Custom functions that should not trigger C001
make_connection :: proc(db: string) -> string {
    return "connected to " + db
}

new_buffer :: proc(size: int) -> []u8 {
    return make([]u8, size)
}

maker :: proc(t: string) -> string {
    return "made " + t
}

newbie :: proc(name: string) -> string {
    return "new " + name
}

make_something_else :: proc() -> int {
    return 42
}

new_instance :: proc(d: Data) -> Data {
    return d
}

make_custom_thing :: proc(value: int) -> int {
    return value * 2
}