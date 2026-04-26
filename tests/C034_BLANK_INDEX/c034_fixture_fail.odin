package fixture_c034_fail

// C034: for v, _ in — blank index is unnecessary.

iterate :: proc(items: []int) {
    for v, _ in items {  // C034 — use: for v in items
        _ = v
    }
}

iterate_strings :: proc(names: []string) {
    for name, _ in names {  // C034
        _ = name
    }
}
