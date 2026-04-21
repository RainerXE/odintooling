package c020_fail

// C020 fail fixture: short names not in allowlist — violations expected.

bad_local_vars :: proc() -> int {
    a := 1        // 'a' — single char, not in allowlist
    b := 2        // 'b' — single char, not in allowlist
    return a + b
}

bad_params :: proc(p: int, q: float) -> int {
    // 'p' and 'q' are short params not in allowlist
    return p
}

mixed_proc :: proc(count: int, v: float) -> float {
    // 'count' is fine; 'v' is short and not in allowlist
    s := count  // 's' is a bad local var name
    return v * float(s)
}
