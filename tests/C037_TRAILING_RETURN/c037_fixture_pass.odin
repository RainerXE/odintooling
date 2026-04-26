package fixture_c037_pass

// C037 should NOT fire on these patterns.

// Correct: no trailing return
setup :: proc() {
    _ = 42
}

// Correct: early return in conditional — NOT trailing
process :: proc(ok: bool) {
    if !ok {
        return  // early return — fine
    }
    _ = 42
}

// Correct: function with return type — return is needed
compute :: proc() -> int {
    return 42
}

// Correct: return with value in non-void proc
get_flag :: proc() -> bool {
    x := true
    return x
}
