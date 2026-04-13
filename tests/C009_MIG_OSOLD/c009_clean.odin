package test_c009_clean

import "core:os"   // OK: new unified API

test :: proc() {
    _ = os.read_file
}
