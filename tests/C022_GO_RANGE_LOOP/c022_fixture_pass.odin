package fixture_c022_pass

// C022 should NOT fire on any of these patterns.

// Correct Odin range/iteration syntax
iterate_correctly :: proc(items: []int) {
	for v, i in items { _ = v; _ = i }        // correct: value first, index second
	for v in items     { _ = v }               // correct: value only
	for i in 0..<len(items) { _ = i }          // correct: index range
	for i in 0..=len(items)-1 { _ = i }        // correct: inclusive range
}

// Odin 0..<n syntax uses "range" as a keyword internally but not in this form
range_expr :: proc() {
	for i in 0..<10 { _ = i }                 // correct — not a Go-style range call
}

// Comment mentions range — must NOT be flagged
// for i, v := range items is Go syntax
comment_only :: proc() {
	_ := 0
}
