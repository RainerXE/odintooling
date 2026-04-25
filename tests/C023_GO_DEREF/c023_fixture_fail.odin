package fixture_c023_fail

// C023 violations: C-style *ptr dereference — Odin uses postfix ptr^

SomeStruct :: struct { value: int }

// Case 1: assignment RHS dereference
read_ptr :: proc(p: ^SomeStruct) -> int {
	v := *p        // C023 — use: v := p^
	return v.value
}

// Case 2: in expression
sum_ptrs :: proc(a, b: ^int) -> int {
	return *a + *b  // C023 on *a — use: a^ + b^
}

// Case 3: after return
get_value :: proc(p: ^int) -> int {
	return *p      // C023 — use: return p^
}
