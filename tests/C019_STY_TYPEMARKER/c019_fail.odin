package c019_fail

import "core:mem"

Player :: struct { hp: int }

// FAIL: explicit type annotations missing required suffixes

// pointer without _ptr
proc_bad_pointer :: proc(player: ^Player) {  // C019
    _ = player
}

// slice without _slice
proc_bad_slice :: proc() {
    players: []Player = nil  // C019
    _ = players
}

// map without _map
proc_bad_map :: proc() {
    scores: map[string]int  // C019
    _ = scores
}

// allocator without _alloc
proc_bad_alloc :: proc(a: mem.Allocator) {  // C019
    _ = a
}

// cstring without _cstr
proc_bad_cstring :: proc() {
    label: cstring = nil  // C019
    _ = label
}

// FAIL: inferred := missing required suffixes

proc_bad_inferred :: proc() {
    // pointer from new() without _ptr
    p := new(Player)         // C019
    // slice from make without _slice
    s := make([]Player, 10)  // C019
    // map from make without _map
    m := make(map[string]int) // C019
    _ = p
    _ = s
    _ = m
}
