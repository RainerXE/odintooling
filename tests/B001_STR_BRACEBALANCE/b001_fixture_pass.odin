package b001_pass

// B001 pass: all braces balanced
// No B001 violations expected.

// Braces inside strings/comments must NOT be counted.
_ :: proc() {
    s := "hello { world }"
    r := `raw { with } braces`
    c := '{'
    // { this comment brace is ignored }
    /* nested /* block */ comment { } */
    _ = s
    _ = r
    _ = c
}

Foo :: struct {
    x: int,
    y: int,
}

nested :: proc() {
    if true {
        for i := 0; i < 3; i += 1 {
            _ = i
        }
    }
}
