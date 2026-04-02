package main
import "core"
main :: proc() {
    data := make([]int, 10)  // This should be excluded due to core/ path
}
