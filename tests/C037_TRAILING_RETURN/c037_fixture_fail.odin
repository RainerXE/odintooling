package fixture_c037_fail

import "core:fmt"

// C037: trailing `return` at end of void proc is redundant.

print_items :: proc(items: []int) {
    for v in items {
        fmt.println(v)
    }
    return  // C037 — remove this
}

setup :: proc() {
    _ = 42
    return  // C037
}
