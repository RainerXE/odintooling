package lib

import "core:mem"

Error :: enum { None, Failed }

risky :: proc() -> Error { return .None }
quiet :: proc() -> int { return 0 }
pair  :: proc() -> (int, Error) { return 0, .None }

// an allocator error is optional in Odin and ignored all the time: not reported
alloc_only :: proc() -> mem.Allocator_Error { return nil }

// a group returns an error only when every procedure it lists does
risky_a :: proc() -> Error { return .None }
risky_b :: proc(n: int) -> Error { return .None }
risky_group :: proc{risky_a, risky_b}

mixed_a :: proc() -> Error { return .None }
mixed_b :: proc(n: int) -> int { return n }
mixed_group :: proc{mixed_a, mixed_b}
