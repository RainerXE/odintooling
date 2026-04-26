package fixture_c033_pass

import "core:strings"

// C033 should NOT fire on any of these patterns.

// Case 1: correct — defer strings.builder_destroy present
build_string :: proc() -> string {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    strings.write_string(&sb, "hello ")
    strings.write_string(&sb, "world")
    return strings.clone(strings.to_string(sb))  // clone before destroy
}

// Case 2: correct — result returned (caller takes builder)
make_builder :: proc() -> strings.Builder {
    sb := strings.builder_make()
    return sb  // returned — caller is responsible
}

// Case 3: correct — explicit destroy (non-defer)
explicit_cleanup :: proc() {
    sb := strings.builder_make()
    strings.write_string(&sb, "data")
    _ = strings.to_string(sb)
    strings.builder_destroy(&sb)
}

// Case 4: suppression
suppressed_builder :: proc() {
    sb := strings.builder_make()  // olt:ignore C033
    _ = sb
}
