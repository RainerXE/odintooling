package test_c012_clean

import "core:mem"

// C012-S1: _owned present — no INFO
test_s1_clean :: proc() {
    results_owned := make([]string, 0, 16)
    data_owned    := new(int)
    _              = results_owned
    _              = data_owned
}

// C012-S2: _view or _borrowed present — no INFO
test_s2_clean :: proc(buf: []u8) {
    header_view     := buf[0:4]
    chunk_borrowed  := buf[4:]
    _                = header_view
    _                = chunk_borrowed
}

// C012-S3: alloc in name — no INFO
test_s3_clean :: proc() {
    track: mem.Tracking_Allocator
    my_alloc    := mem.tracking_allocator(&track)
    _ = my_alloc
}
