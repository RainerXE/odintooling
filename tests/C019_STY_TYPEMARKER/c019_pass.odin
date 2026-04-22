package c019_pass

import "core:mem"

// PASS: all names follow the type marker convention

Player :: struct { hp: int }

// Parameters with correct suffixes
proc_correct_params :: proc(
    player_ptr:    ^Player,
    players_slice: []Player,
    players_dyn:   [dynamic]Player,
    players_arr:   [4]Player,
    scores_map:    map[string]int,
    arena_alloc:   mem.Allocator,
    label_cstr:    cstring,
    callback_fn:   proc(x: int),
) {}

// Local variables with correct suffixes
proc_correct_locals :: proc() {
    player_ptr:    ^Player    = nil
    players_slice: []Player   = nil
    players_dyn:   [dynamic]Player
    scores_map:    map[string]int
    arena_alloc:   mem.Allocator
    label_cstr:    cstring    = nil
}

// Value types — no suffix needed
proc_value_types :: proc() {
    count:  int    = 0
    name:   string = "hello"
    active: bool   = true
    player: Player
}

// Inferred := with correct suffixes
proc_inferred_correct :: proc() {
    player_ptr    := new(Player)
    players_slice := make([]Player, 10)
    players_dyn   := make([dynamic]Player)
    scores_map    := make(map[string]int)
    raw_ptr       := &player_ptr   // & → pointer, has _ptr
    _ = player_ptr
    _ = players_slice
    _ = players_dyn
    _ = scores_map
    _ = raw_ptr
}

// Suppression should silence the rule
proc_suppressed :: proc() {
    p: ^Player = nil  // odin-lint:ignore C019
    _ = p
}
