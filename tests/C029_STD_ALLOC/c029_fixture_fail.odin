package fixture_c029_fail

import "core:fmt"
import "core:os"
import "core:strings"

// C029 violations: stdlib allocating procs whose results are never freed.

// Case 1: strings.split without defer delete
process_csv :: proc(line: string) {
    parts := strings.split(line, ",")  // C029 — needs defer delete(parts)
    for p in parts { _ = p }
}

// Case 2: strings.clone without defer delete
duplicate_name :: proc(name: string) -> string {
    // Wrong: cloned but not freed before returning a different value
    copy := strings.clone(name)   // C029 — no defer delete(copy)
    _ = copy
    return ""
}

// Case 3: fmt.aprintf without defer delete
build_message :: proc(code: int) {
    msg := fmt.aprintf("error code: %d", code)  // C029
    _ = msg
}

// Case 4: strings.join without defer delete
join_paths :: proc(parts: []string) {
    result := strings.join(parts, "/")  // C029
    _ = result
}

// Case 5: os.read_entire_file_from_path without defer delete
read_config :: proc(path: string) {
    data, ok := os.read_entire_file_from_path(path, context.allocator)  // C029
    if !ok { return }
    _ = data
}

// Case 6: strings.concatenate without defer delete
combine :: proc(a, b: string) {
    result := strings.concatenate([]string{a, " ", b})  // C029
    _ = result
}
