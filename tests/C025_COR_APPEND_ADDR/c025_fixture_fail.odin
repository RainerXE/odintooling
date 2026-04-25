package fixture_c025_fail

// C025 violations: append(slice, v) missing the address-of operator.
// Odin's append mutates the slice through a pointer; append(&slice, v) is correct.

// Case 1: plain identifier — most common mistake
add_items :: proc() {
	items := make([dynamic]int)
	defer delete(items)
	append(items, 1)    // C025 — should be append(&items, 1)
	append(items, 2)    // C025
}

// Case 2: different element types
collect_strings :: proc() -> [dynamic]string {
	result := make([dynamic]string)
	for i in 0..<5 {
		s := "hello"
		append(result, s)  // C025 — should be append(&result, s)
	}
	return result
}

// Case 3: appending to a field is harder to detect but bare slice var is flagged
append_bytes :: proc() {
	buf := make([dynamic]u8)
	defer delete(buf)
	append(buf, 0xFF)  // C025
}
