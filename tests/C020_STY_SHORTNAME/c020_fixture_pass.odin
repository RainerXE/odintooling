package c020_pass

// C020 pass fixture: all names are either long enough or on the allowlist.

loop_example :: proc() -> int {
    total := 0
    for i in 0..<10 {       // i is in the default allowlist — OK
        total += i
    }
    return total
}

coordinate_proc :: proc(x: int, y: int, z: int) -> int {
    // x, y, z are coordinates — in allowlist, OK
    return x + y + z
}

database_proc :: proc(db: string, id: int) -> bool {
    // db and id are in allowlist — OK
    return len(db) > 0 && id > 0
}

descriptive_names :: proc(count: int, name: string) -> bool {
    result := count > 0       // 'result' is long enough — OK
    prefix := name[:2]        // 'prefix' is long enough — OK
    return result && len(prefix) > 0
}
