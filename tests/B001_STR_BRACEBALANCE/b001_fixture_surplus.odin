package b001_surplus

// B001 fail: surplus closing brace — extra } after the proc body
// Expected: B001 violation for the unexpected closing brace.

baz :: proc() {
    y := 99
    _ = y
}
} // surplus brace
