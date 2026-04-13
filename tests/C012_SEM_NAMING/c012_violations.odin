package test_c012_violations

import "core:mem"

// C012-S1: make/new without _owned — should fire INFO
test_s1 :: proc() {
    results := make([]string, 0, 16)    // INFO: no _owned
    data    := new(int)                 // INFO: no _owned
    _        = results
    _        = data
}

// C012-S2: slice without _view/_borrowed — should fire INFO
test_s2 :: proc(buf: []u8) {
    header := buf[0:4]                  // INFO: no _view or _borrowed
    chunk  := buf[4:]                   // INFO: no _view or _borrowed
    _       = header
    _       = chunk
}

// C012-S3: allocator call without alloc in name — should fire INFO
test_s3 :: proc() {
    track: mem.Tracking_Allocator
    a := mem.tracking_allocator(&track) // INFO: no alloc/allocator in name
    _ = a
}
