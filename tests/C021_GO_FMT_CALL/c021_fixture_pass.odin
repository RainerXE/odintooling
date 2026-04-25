package fixture_c021_pass

import "core:fmt"

// C021 should NOT fire on these patterns.

// Correct Odin fmt usage
odin_style_output :: proc() {
	fmt.println("hello world")       // correct
	fmt.printf("value: %d\n", 42)   // correct
	fmt.print("no newline")          // correct
	s := fmt.tprintf("x=%d", 1)     // correct
	_ = s
	t := fmt.aprintf("owned: %d", 2) // correct
	_ = t
}

// Go names in comments or strings must NOT be flagged
comments_and_strings :: proc() {
	// fmt.Println is the Go equivalent of fmt.println
	msg := "use fmt.Println in Go, but fmt.println in Odin"
	_ = msg
}
