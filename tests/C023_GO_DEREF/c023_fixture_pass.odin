package fixture_c023_pass

// C023 should NOT fire on any of these patterns.

SomeStruct :: struct { value: int }

// Correct Odin postfix dereference
read_ptr :: proc(p: ^SomeStruct) -> int {
	v := p^         // correct: postfix ^
	return v.value
}

// Multiplication — must NOT be flagged
multiply :: proc(a, b: int) -> int {
	return a * b    // * here is multiplication
}

// Pointer type annotation — must NOT be flagged
PtrType :: ^SomeStruct
PtrPtr  :: ^^SomeStruct

// Slice of pointers — must NOT be flagged
slice_of_ptrs :: proc() -> []*SomeStruct {
	return nil
}

// Bitwise operations — must NOT be flagged
bitwise :: proc(a, b: int) -> int {
	return a & b
}
