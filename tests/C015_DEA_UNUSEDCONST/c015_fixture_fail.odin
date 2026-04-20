package c015_fail

// C015 fail fixture: private constants/variables never referenced — violations expected.

@(private)
DEAD_CONSTANT :: 42

@(private)
ANOTHER_DEAD :: "unused string"

@(private)
dead_variable: int = 0

// Public procs are NOT subject to C015.
PUBLIC_CONST :: 100

public_entry :: proc() -> int {
    // None of the @(private) symbols above are referenced here.
    return PUBLIC_CONST
}
