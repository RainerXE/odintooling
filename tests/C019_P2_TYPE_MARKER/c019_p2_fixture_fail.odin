package fixture_c019_p2_fail

// Procs with non-value return types — graph will index these.
get_player     :: proc() -> ^int  { return new(int) }
get_items      :: proc() -> []int { return nil }
get_lookup     :: proc() -> map[string]int { return nil }
get_label      :: proc() -> cstring { return nil }

// ── C019 Phase 2 failures: inferred := calls where name lacks required suffix ──

use_player :: proc() {
    player := get_player()   // C019: ^int return → needs _ptr suffix
    _ = player
}

use_items :: proc() {
    items := get_items()     // C019: []int return → needs _slice suffix
    _ = items
}

use_lookup :: proc() {
    lookup := get_lookup()   // C019: map return → needs _map suffix
    _ = lookup
}

use_label :: proc() {
    label := get_label()     // C019: cstring return → needs _cstr suffix
    _ = label
}
