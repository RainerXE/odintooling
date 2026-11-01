package c001_ownership

// Each of these must still be reported (line numbers are checked by the test runner).

// never freed, returned or stored                                  -> line 7
leaks :: proc(n: int) {
	buf := make([]int, n)
	buf[0] = 1
}

// only read                                                        -> line 13
reads :: proc() -> int {
	xs := make([]int, 4)
	total := 0
	for x in xs { total += x }
	return total
}

// assigned and dropped                                             -> line 21
mixed :: proc() {
	a := make([]int, 2)
	_ = a
}
