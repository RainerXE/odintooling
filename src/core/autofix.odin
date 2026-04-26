// autofix.odin — fix generation, proposal (--propose), and in-place application (--fix).
// generate_fixes converts Diagnostic.fix strings into FileEdit structs; apply_fixes
// writes the edits back to disk; propose_fixes prints a human-readable diff.
package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// Autofix — machine-applicable fix generation and application
// =============================================================================
//
// Currently supports:
//   C001 — inserts 'defer delete(var)' or 'defer free(var)' after allocation
//
// Usage:
//   --fix      applies fixes in-place to source files
//   --propose  prints a before/after diff without writing
// =============================================================================

// FixEdit describes a single-line insertion or replacement fix.
FixEdit :: struct {
    file:         string,
    line:         int,    // 1-indexed target line
    new_text:     string, // replacement or inserted line content (no trailing \n)
    rule_id:      string,
    message:      string,
    is_unsafe:    bool,   // true = changes API surface; requires --unsafe-fix
    replace_line: bool,   // true = replace line; false = insert new line AFTER
}

// generate_fixes extracts machine-applicable fixes from diagnostics.
// Safe fixes (C001) are always generated. Unsafe fixes (C009) require
// allow_unsafe = true (i.e. --unsafe-fix flag).
generate_fixes :: proc(diags: []Diagnostic, allow_unsafe: bool = false) -> [dynamic]FixEdit {
    edits := make([dynamic]FixEdit)

    // Build a file-content cache so we read each file at most once.
    file_lines_cache := make(map[string][]string)
    defer {
        for _, lines in file_lines_cache { delete(lines) }
        delete(file_lines_cache)
    }

    for d in diags {
        if d.rule_id != "C001" { continue }
        if d.line <= 0         { continue }

        // Load file lines (cached). We must clone each line string because
        // strings.split returns views into the original data buffer, and the
        // data buffer would be freed at the end of the if-block (Odin defer
        // scopes to the block, not the procedure).
        lines, cached := file_lines_cache[d.file]
        if !cached {
            data, err := os.read_entire_file_from_path(d.file, context.allocator)
            if err != nil { continue }
            raw_lines := strings.split(string(data), "\n")
            // Clone each line so the slice is independent of data.
            cloned := make([]string, len(raw_lines))
            for l, i in raw_lines { cloned[i] = strings.clone(l) }
            delete(raw_lines)
            delete(data)
            lines = cloned
            file_lines_cache[d.file] = lines
        }

        if d.line > len(lines) { continue }
        src_line := lines[d.line - 1]

        // Extract variable name from the allocation line.
        var_name := fix_extract_lhs(src_line)
        if var_name == "" { continue }

        // Determine free function: delete for slice/map/dynamic, free for pointer.
        free_fn := "delete" if strings.contains(src_line, "make(") else "free"

        // Preserve indentation of the allocation line.
        indent := fix_extract_indent(src_line)

        new_line := fmt.tprintf("%sdefer %s(%s)", indent, free_fn, var_name)

        append(&edits, FixEdit{
            file     = d.file,
            line     = d.line,
            new_text = new_line,
            rule_id  = "C001",
            message  = fmt.tprintf("insert 'defer %s(%s)' after line %d", free_fn, var_name, d.line),
        })
    }

    // C009 unsafe fix: replace 'import "core:os/old"' with 'import "core:os"'.
    // Marked unsafe because the new core:os API differs from core:os/old.
    if allow_unsafe {
        for d in diags {
            if d.rule_id != "C009" { continue }
            if d.line <= 0         { continue }

            lines, cached := file_lines_cache[d.file]
            if !cached {
                data, err := os.read_entire_file_from_path(d.file, context.allocator)
                if err != nil { continue }
                raw_lines := strings.split(string(data), "\n")
                cloned := make([]string, len(raw_lines))
                for l, i in raw_lines { cloned[i] = strings.clone(l) }
                delete(raw_lines)
                delete(data)
                lines = cloned
                file_lines_cache[d.file] = lines
            }

            if d.line > len(lines) { continue }
            src_line := lines[d.line - 1]
            if !strings.contains(src_line, "core:os/old") { continue }

            // Replace the old import line with the new one.
            new_line, _ := strings.replace(src_line, "core:os/old", "core:os", 1)
            append(&edits, FixEdit{
                file         = d.file,
                line         = d.line,
                new_text     = new_line,
                rule_id      = "C009",
                message      = "replace 'core:os/old' with 'core:os'",
                is_unsafe    = true,
                replace_line = true,
            })
        }
    }

    return edits
}

// apply_fixes writes fixes in-place, grouped per file.
// Returns (files_modified, had_error).
apply_fixes :: proc(edits: []FixEdit) -> (int, bool) {
    if len(edits) == 0 { return 0, false }

    // Group edits by file.
    by_file := make(map[string][dynamic]FixEdit)
    defer {
        for _, v in by_file { delete(v) }
        delete(by_file)
    }
    for e in edits {
        list, ok := &by_file[e.file]
        if !ok {
            by_file[e.file] = make([dynamic]FixEdit)
            list = &by_file[e.file]
        }
        append(list, e)
    }

    files_modified := 0
    had_error       := false

    for file_path, file_edits in by_file {
        ok := apply_file_edits(file_path, file_edits[:])
        if ok {
            files_modified += 1
            fmt.printf("fixed: %s (%d edit(s))\n", file_path, len(file_edits))
        } else {
            fmt.fprintf(os.stderr, "error: could not apply fixes to %s\n", file_path)
            had_error = true
        }
    }

    return files_modified, had_error
}

// propose_fixes prints a before/after diff to stdout without modifying files.
propose_fixes :: proc(edits: []FixEdit) {
    if len(edits) == 0 {
        fmt.println("No machine-applicable fixes available.")
        return
    }

    // Group by file for a tidy display.
    by_file := make(map[string][dynamic]FixEdit)
    defer {
        for _, v in by_file { delete(v) }
        delete(by_file)
    }
    for e in edits {
        list, ok := &by_file[e.file]
        if !ok {
            by_file[e.file] = make([dynamic]FixEdit)
            list = &by_file[e.file]
        }
        append(list, e)
    }

    for file_path, file_edits in by_file {
        data, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil {
            fmt.fprintf(os.stderr, "warning: cannot read %s for proposal\n", file_path)
            continue
        }
        defer delete(data)
        lines := strings.split(string(data), "\n")
        defer delete(lines)

        fmt.printf("--- %s\n", file_path)
        fmt.printf("+++ %s (proposed)\n", file_path)

        for e in file_edits {
            if e.line <= 0 || e.line > len(lines) { continue }

            if e.replace_line {
                // Show the old line and the replacement.
                ctx_start := max(1, e.line - 1)
                for i := ctx_start; i < e.line && i <= len(lines); i += 1 {
                    fmt.printf(" %4d | %s\n", i, lines[i-1])
                }
                fmt.printf("-%4d | %s\n", e.line, lines[e.line-1])
                fmt.printf("+%4d | %s\n", e.line, e.new_text)
                if e.is_unsafe { fmt.println("       ^ unsafe fix") }
            } else {
                // Show 2 lines of context before insertion.
                ctx_start := max(1, e.line - 1)
                for i := ctx_start; i <= e.line && i <= len(lines); i += 1 {
                    fmt.printf(" %4d | %s\n", i, lines[i-1])
                }
                fmt.printf("+%4d | %s\n", e.line + 1, e.new_text)
            }
            fmt.println()
        }
    }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// fix_extract_indent returns the leading whitespace of a line.
@(private)
fix_extract_indent :: proc(line: string) -> string {
    for i := 0; i < len(line); i += 1 {
        if line[i] != ' ' && line[i] != '\t' {
            return line[:i]
        }
    }
    return ""
}

// fix_extract_lhs returns the variable name on the left-hand side of ':='.
// Returns "" if the pattern is not found or the name is blank/multi-assign.
@(private)
fix_extract_lhs :: proc(line: string) -> string {
    idx := strings.index(line, " :=")
    if idx < 0 { return "" }
    lhs := strings.trim(line[:idx], " \t")
    // Skip multi-variable declarations (contains comma).
    if strings.contains(lhs, ",") { return "" }
    // Strip any leading qualifier (e.g. "_ =" style — shouldn't happen here).
    if lhs == "_" || lhs == "" { return "" }
    return lhs
}

// apply_file_edits reads the file, applies insertions and replacements, writes back.
@(private)
apply_file_edits :: proc(file_path: string, edits: []FixEdit) -> bool {
    data, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil { return false }
    defer delete(data)

    lines := strings.split(string(data), "\n")
    defer delete(lines)

    // Separate insertions and replacements.
    insert_map  := make(map[int][dynamic]string) // after_line → lines to insert
    replace_map := make(map[int]string)          // line → replacement text
    defer {
        for _, v in insert_map { delete(v) }
        delete(insert_map)
        delete(replace_map)
    }

    for e in edits {
        if e.replace_line {
            replace_map[e.line] = e.new_text
        } else {
            list, ok := &insert_map[e.line]
            if !ok {
                insert_map[e.line] = make([dynamic]string)
                list = &insert_map[e.line]
            }
            append(list, e.new_text)
        }
    }

    // Build output lines.
    result := make([dynamic]string)
    defer delete(result)

    for i := 0; i < len(lines); i += 1 {
        line_no := i + 1
        if replacement, ok := replace_map[line_no]; ok {
            append(&result, replacement)
        } else {
            append(&result, lines[i])
        }
        if inserts, ok := insert_map[line_no]; ok {
            for ins in inserts {
                append(&result, ins)
            }
        }
    }

    out := strings.join(result[:], "\n")
    defer delete(out)

    write_err := os.write_entire_file(file_path, transmute([]u8)out)
    return write_err == nil
}
