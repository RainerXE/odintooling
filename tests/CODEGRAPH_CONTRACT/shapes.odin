// Fixture for scripts/test_codegraph_contract.sh. Expected graph:
//   callers of `helper`       = main, outer, inner   (all three call it)
//   callers of `after_nested` = outer ONLY           (the call comes after the nested
//                                                     proc `inner` has ended; a "last proc
//                                                     that started before this line" rule
//                                                     would wrongly say `inner`)
package demo

Colour :: enum {
	Red,
	Green,
	Blue,
}

Point :: struct {
	x, y: int,
}

Shape :: union {
	Point,
}

helper :: proc(x: int) -> int {
	return x + 1
}

after_nested :: proc() {}

outer :: proc() {
	inner :: proc() {
		_ = helper(1)
	}
	inner()
	after_nested() // after `inner` ended: belongs to `outer`, not `inner`
	_ = helper(2)
}

main :: proc() {
	_ = helper(3)
	outer()
}
