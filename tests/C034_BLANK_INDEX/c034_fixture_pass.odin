package fixture_c034_pass

// C034 should NOT fire on these patterns.

// Correct: value-only iteration
iterate :: proc(items: []int) {
    for v in items { _ = v }
}

// Correct: using the index
iterate_with_idx :: proc(items: []int) {
    for v, i in items { _ = v; _ = i }  // using both — fine
}

// Correct: blank value, keep index
reverse_idx :: proc(items: []int) {
    for _, i in items { _ = i }  // keeping index, blank value — fine
}
