package test_c016

// C016 PASS fixture — all local vars are snake_case, no violations expected

good_proc :: proc() {
    player_count := 0
    player_ptr   := &player_count
    total_score  := 100
    is_valid     := true
    file_path    := "test.odin"
    max_items    := 64

    // Single-char vars are exempt (loop counters, math vars)
    i := 0
    x := 1.0
    n := len(file_path)

    // _ prefix vars are exempt
    _unused := player_count + 1

    // Reassignments (=) are not checked — only := declarations
    player_count = player_count + 1
    total_score  = total_score - 10

    _ = player_ptr
    _ = is_valid
    _ = max_items
    _ = i
    _ = x
    _ = n
    _ = _unused
}

another_proc :: proc() -> int {
    result := 0
    temp_val := 42
    result = temp_val * 2
    return result
}
