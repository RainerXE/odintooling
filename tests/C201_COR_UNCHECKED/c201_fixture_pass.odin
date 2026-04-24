package c201_test

import "core:os"

// C201 clean: all error returns are handled

good_open :: proc() -> bool {
    h, err := os.open("foo.txt")
    if err != nil { return false }
    defer os.close(h)
    return true
}

good_write :: proc(h: os.Handle) -> bool {
    _, err := os.write(h, []u8{1, 2, 3})
    return err == nil
}

good_non_error :: proc() {
    // os.is_file returns bool — C201 must not fire
    _ = os.is_file("foo.txt")
}
