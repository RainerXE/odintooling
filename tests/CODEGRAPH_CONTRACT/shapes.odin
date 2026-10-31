// Fixture for scripts/test_codegraph_contract.sh. Expected graph:
//   callers of `helper`       = main, outer, inner   (all three call it)
//   callers of `after_nested` = outer ONLY           (the call comes after the nested
//                                                     proc `inner` has ended; a "last proc
//                                                     that started before this line" rule
//                                                     would wrongly say `inner`)
//   `area` is a group over `area_point`: references edge area -> area_point, one area_point node
//   callers of `util` (package lib, a sibling directory) = main   (pkg.fn() through an import)
package demo

import "core:fmt"
import "lib"

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

area_point :: proc(p: Point) -> int {
	return p.x * p.y
}

// A procedure group: ONE function node for `area`, a `references` edge to each member,
// and no second copy of `area_point` created from the name inside the braces.
area :: proc {
	area_point,
}

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
	_ = lib.util()        // qualified call into another package of the project
	fmt.println("hi")     // qualified call into core: (outside the project)
}
