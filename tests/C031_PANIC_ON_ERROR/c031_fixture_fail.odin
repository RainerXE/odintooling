package fixture_c031_fail

import "core:os"

// C031: panic() handling an expected runtime failure should return an error.

// Case 1: panic after !ok — most common Go habit
load_file :: proc(path: string) -> []byte {
    data, ok := os.read_entire_file(path)
    if !ok {
        panic("file not found")   // C031 — return an error instead
    }
    return data
}

// Case 2: panic after err != nil
connect :: proc(addr: string) {
    conn, err := _fake_connect(addr)
    if err != nil {
        panic("connection failed")  // C031
    }
    _ = conn
}

// Case 3: inline panic on same line as condition
quick_load :: proc(path: string) -> []byte {
    data, ok := os.read_entire_file(path)
    if !ok { panic("cannot load") }   // C031
    return data
}

// Fake helpers to make the fixture compile
FakeErr :: enum { None, Fail }
FakeConn :: distinct int

_fake_connect :: proc(addr: string) -> (FakeConn, FakeErr) {
    return 0, .None
}
