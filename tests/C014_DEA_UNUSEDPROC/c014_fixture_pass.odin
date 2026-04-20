package c014_pass

// C014 pass fixture: private procs that ARE called — no dead code violation expected.

@(private)
helper_do_work :: proc(x: int) -> int {
    return x * 2
}

public_entry :: proc() -> int {
    // helper_do_work is private but called here, so C014 must NOT fire.
    return helper_do_work(21)
}
