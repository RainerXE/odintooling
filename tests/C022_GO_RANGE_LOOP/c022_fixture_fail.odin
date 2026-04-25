package fixture_c022_fail

// C022 violations: Go-style `for i, v := range collection` — doesn't compile in Odin.

// Case 1: basic range loop — classic Go mistake
iterate_slice :: proc(items: []int) {
	for i, v := range items {     // C022 — use: for v, i in items
		_ = i; _ = v
	}
}

// Case 2: only index
iterate_index :: proc(items: []string) {
	for i := range items {        // C022 — use: for _, i in items or for i in 0..<len(items)
		_ = i
	}
}
