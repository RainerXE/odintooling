package fixture_c033_fail

import "core:strings"

// C033 violations: strings.Builder allocated without defer strings.builder_destroy.

// Case 1: builder_make without destroy
build_string :: proc() -> string {
    sb := strings.builder_make()  // C033 — needs defer strings.builder_destroy(&sb)
    strings.write_string(&sb, "hello ")
    strings.write_string(&sb, "world")
    return strings.to_string(sb)
}

// Case 2: builder in loop processing
format_items :: proc(items: []string) {
    sb := strings.builder_make()  // C033
    for item in items {
        strings.write_string(&sb, item)
        strings.write_string(&sb, "\n")
    }
    _ = strings.to_string(sb)
}
