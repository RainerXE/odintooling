package test_c010_clean

test_types :: proc() {
    arr: [dynamic]int           // OK: standard dynamic array
    _ = arr
}
