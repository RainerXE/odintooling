package b001_unclosed

// B001 fail: unclosed brace — missing closing } for the proc body
// Expected: B001 violation for the opening brace.

bar :: proc() {
    x := 42
    _ = x
// closing brace deliberately omitted
