package fixture_c029_pass

import "core:fmt"
import "core:os"
import "core:strings"

// C029 should NOT fire on any of these patterns.

// Case 1: correct — defer delete present
process_csv :: proc(line: string) {
    parts := strings.split(line, ",")
    defer delete(parts)
    for p in parts { _ = p }
}

// Case 2: correct — result returned (ownership transferred to caller)
get_name :: proc(name: string) -> string {
    return strings.clone(name)  // caller owns the result
}

// Case 3: correct — custom allocator (caller controls lifetime)
process_with_arena :: proc(line: string, allocator := context.allocator) {
    parts := strings.split(line, ",", allocator)
    for p in parts { _ = p }
}

// Case 4: correct — temp allocator (not heap, cleaned up by caller)
temp_format :: proc(code: int) -> string {
    return fmt.tprintf("code=%d", code)  // temp allocator, not C029's concern
}

// Case 5: correct — defer delete for aprintf
log_message :: proc(code: int) {
    msg := fmt.aprintf("code: %d", code)
    defer delete(msg)
    _ = msg
}

// Case 6: correct — read file and defer delete
read_file :: proc(path: string) -> bool {
    data, ok := os.read_entire_file_from_path(path, context.allocator)
    if !ok { return false }
    defer delete(data)
    _ = data
    return true
}

// Case 7: suppression
suppressed_alloc :: proc(s: string) {
    parts := strings.split(s, ",")  // olt:ignore C029
    _ = parts
}
