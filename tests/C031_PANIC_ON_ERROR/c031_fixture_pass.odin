package fixture_c031_pass

// C031 should NOT fire on these patterns.

// Programming-error panics (invariant violations) are fine
assert_positive :: proc(n: int) {
    if n <= 0 { panic("BUG: expected positive value") }  // OK: programming error
}

unreachable_branch :: proc(x: int) {
    switch x {
    case 0: // handled
    case:
        panic("unreachable")  // OK: invariant
    }
}

unimplemented_feature :: proc() {
    panic("unimplemented")  // OK: TODO marker
}

// Panic in init proc is fine (process startup failure)
_module_init :: proc() {
    if _fake_setup() != .None {
        panic("module init failed")  // OK: init proc
    }
}

// Suppression
suppressed_case :: proc() -> []byte {
    data, ok := _fake_read()
    if !ok {
        panic("cannot load")  // olt:ignore C031
    }
    return data
}

// Fake helpers
FakeErr :: enum { None, Fail }
_fake_setup :: proc() -> FakeErr { return .None }
_fake_read  :: proc() -> ([]byte, bool) { return nil, true }
