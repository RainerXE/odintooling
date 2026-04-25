package fixture_c025_pass

// C025 should NOT fire on these patterns.

// Case 1: correct — address-of operator present
add_items_correct :: proc() {
	items := make([dynamic]int)
	defer delete(items)
	append(&items, 1)   // correct
	append(&items, 2)   // correct
}

// Case 2: correct — field access (not a plain identifier)
// (not flagged by C025 since first arg is a selector expression)
SomeStruct :: struct { items: [dynamic]int }
add_to_struct :: proc(s: ^SomeStruct) {
	append(&s.items, 42)  // correct
}

// Case 3: suppression
suppressed :: proc() {
	items := make([dynamic]int)
	defer delete(items)
	append(items, 99)  // olt:ignore C025
}
