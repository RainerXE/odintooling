package main

import "core"
import "core:fmt"

main :: proc() {
    // PERF: Hot path - allocations are intentional for performance
    hot_data := new(Data)
    // No defer free - intentional for performance
}

regular_func :: proc() {
    // Regular allocation - should have normal message
    regular_data := new(Data)
    // Missing defer free(regular_data)
}

Data :: struct {}
