package c019_edge

// EDGE: proc types → _fn suffix
Callback :: proc(x: int) -> int

proc_fn_param :: proc(on_update_fn: proc(x: int)) {
    _ = on_update_fn
}

// EDGE: dynamic array → _dyn suffix (explicit annotation)
proc_dyn_ok :: proc() {
    items_dyn: [dynamic]int
    _ = items_dyn
}

// EDGE: fixed array → _arr suffix
proc_arr_ok :: proc() {
    data_arr: [8]u8
    _ = data_arr
}

// EDGE: multi-pointer → _buf suffix
proc_buf_ok :: proc() {
    data_buf: [^]u8 = nil
    _ = data_buf
}

// EDGE: rawptr → _ptr suffix
proc_raw_ok :: proc() {
    handle_ptr: rawptr = nil
    _ = handle_ptr
}

// EDGE: struct fields are NOT checked
World :: struct {
    player: ^int,          // no _ptr needed on struct fields
    items:  []string,      // no _slice needed on struct fields
}

// EDGE: value types — no suffix needed regardless of name
proc_value_names :: proc() {
    count: int = 0
    _ = count
}

// EDGE: multi-return := — cannot classify, should not fire
some_proc :: proc() -> (^int, []u8) { return nil, nil }
proc_multi_return :: proc() {
    a, b := some_proc()   // cannot classify without OLS — no diagnostic
    _ = a
    _ = b
}
