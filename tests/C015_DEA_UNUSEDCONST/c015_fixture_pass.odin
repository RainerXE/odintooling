package c015_pass

// C015 pass fixture: private constants/variables that ARE referenced — no violation expected.

@(private)
MULTIPLIER :: 3

@(private)
base_value: int = 10

public_compute :: proc(x: int) -> int {
    // MULTIPLIER and base_value are both private but used here — must NOT fire.
    return x * MULTIPLIER + base_value
}
