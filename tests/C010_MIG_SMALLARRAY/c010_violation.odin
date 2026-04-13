package test_c010

test_types :: proc() {
    arr: Small_Array(8, int)   // VIOLATION: superseded
    _ = arr
}
