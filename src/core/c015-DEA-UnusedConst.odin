package core

import "core:fmt"
import "core:os"
import "core:strings"
import sq "../../vendor/odin-sqlite3"

// =============================================================================
// C015: Private constant/variable declared but never referenced  (opt-in)
// =============================================================================
//
// Fires when a package-level constant or variable marked @(private) is never
// referenced anywhere in the project. Detected via a word-boundary text scan
// across all project files after the graph is built.
//
// Requires the code graph to be built first (--export-symbols).
// Enabled via [domains] dead_code = true in odin-lint.toml.
//
// Limitation: names that coincidentally appear in comments, string literals, or
// as substrings of other identifiers are exempt due to word-boundary checking.
// Common short names (e.g. 'x', 'ok') may produce false negatives if they
// appear incidentally. Prefer unique, descriptive names for private constants.
//
// Category: DEAD CODE (info tier, opt-in)
// =============================================================================


// _count_word_occurrences counts word-boundary occurrences of word in content.
@(private="file")
_count_word_occurrences :: proc(content: string, word: string) -> int {
    if len(word) == 0 { return 0 }
    count := 0
    s     := content
    for {
        idx := strings.index(s, word)
        if idx < 0 { break }
        abs  := len(content) - len(s) + idx
        prev := abs == 0              || !is_ident_byte(content[abs-1])
        next := abs+len(word) >= len(content) || !is_ident_byte(content[abs+len(word)])
        if prev && next { count += 1 }
        s = s[idx+len(word):]
    }
    return count
}

// c015_query_dead_consts scans all project files for private constants and
// variables that are never referenced outside their own declaration.
// Returns a slice of Diagnostics; caller is responsible for deleting it.
c015_query_dead_consts :: proc(db: ^GraphDB, all_files: []string) -> []Diagnostic {
    diags := make([dynamic]Diagnostic)

    // Step 1: collect all private constants and variables.
    ConstInfo :: struct { name, file, kind: string, line: int }
    targets := make([dynamic]ConstInfo)
    defer {
        for &t in targets { delete(t.name); delete(t.file); delete(t.kind) }
        delete(targets)
    }

    s, ok := sq.db_prepare(db.conn, `
        SELECT name, file, line, kind FROM nodes
        WHERE kind IN ('constant','variable') AND is_exported = 0
        ORDER BY file, line;`)
    if !ok { return diags[:] }
    defer sq.stmt_finalize(&s)

    for sq.stmt_step(&s) {
        append(&targets, ConstInfo{
            name = strings.clone(sq.stmt_col_text(&s, 0)),
            file = strings.clone(sq.stmt_col_text(&s, 1)),
            line = sq.stmt_col_int(&s, 2),
            kind = strings.clone(sq.stmt_col_text(&s, 3)),
        })
    }

    if len(targets) == 0 { return diags[:] }

    // Step 2: count word-boundary occurrences across all project files.
    ref_counts := make(map[string]int)
    defer delete(ref_counts)

    for f in all_files {
        content, err := os.read_entire_file_from_path(f, context.allocator)
        if err != nil { continue }
        text := string(content)
        for &t in targets {
            ref_counts[t.name] += _count_word_occurrences(text, t.name)
        }
        delete(content)
    }

    // Step 3: any target with count == 1 appears only at its declaration — dead code.
    // Clone file/kind/name into the Diagnostic so it survives the targets defer-delete.
    for t in targets {
        if ref_counts[t.name] <= 1 {
            append(&diags, Diagnostic{
                file      = strings.clone(t.file),
                line      = t.line,
                column    = 1,
                rule_id   = "C015",
                tier      = "dead_code",
                message   = fmt.aprintf(
                    "@(private) %s '%s' is never referenced — consider removing it",
                    t.kind, t.name,
                ),
                has_fix   = true,
                fix       = fmt.aprintf("Delete unused %s '%s'", t.kind, t.name),
                diag_type = .INFO,
            })
        }
    }

    return diags[:]
}
