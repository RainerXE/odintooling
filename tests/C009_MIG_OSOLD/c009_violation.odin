package test_c009

import "core:os/old"   // VIOLATION: deprecated legacy OS package

test :: proc() {
    _ = old.read_file
}
