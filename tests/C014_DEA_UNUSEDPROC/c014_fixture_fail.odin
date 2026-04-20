package c014_fail

// C014 fail fixture: private procs that are NEVER called — dead code violations expected.

@(private)
dead_helper :: proc(x: int) -> int {
    return x + 1
}

@(private="file")
another_dead_helper :: proc() -> string {
    return "unused"
}

// This public proc IS the entry point — no C014 on public procs.
public_entry :: proc() {
    // Neither dead_helper nor another_dead_helper is called here.
}
