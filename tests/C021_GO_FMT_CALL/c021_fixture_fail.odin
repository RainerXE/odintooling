package fixture_c021_fail

import "core:fmt"

// C021 violations: Go-style fmt calls that don't exist in Odin.

go_style_output :: proc() {
	fmt.Println("hello world")       // C021 — use fmt.println
	fmt.Printf("value: %d\n", 42)   // C021 — use fmt.printf
	fmt.Print("no newline")          // C021 — use fmt.print
	s := fmt.Sprintf("x=%d", 1)     // C021 — use fmt.tprintf or fmt.aprintf
	_ = s
}

go_style_errors :: proc() -> string {
	msg := fmt.Sprintf("error: %v", 42)  // C021
	return msg
}
