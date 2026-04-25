package fixture_c019_p2_pass

// Same procs as the fail fixture.
get_player :: proc() -> ^int  { return new(int) }
get_items  :: proc() -> []int { return nil }
get_label  :: proc() -> cstring { return nil }

unknown_return :: proc() -> int { return 42 }  // value return → no suffix needed

// ── PASS: correct suffix on inferred := calls ─────────────────────────────────

use_player_correct :: proc() {
    player_ptr := get_player()   // OK: has _ptr suffix
    _ = player_ptr
}

use_items_correct :: proc() {
    items_slice := get_items()   // OK: has _slice suffix
    _ = items_slice
}

use_label_correct :: proc() {
    label_cstr := get_label()    // OK: has _cstr suffix
    _ = label_cstr
}

// ── PASS: value return — no suffix required ────────────────────────────────────

use_value :: proc() {
    count := unknown_return()    // OK: int return → no suffix needed
    _ = count
}

// ── PASS: proc not in graph — silently skipped ────────────────────────────────

use_stdlib :: proc() {
    // os.open is in stdlib curated list but not our graph → Phase 2 skips
    x := 42
    _ = x
}
