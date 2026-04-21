package core

import "core:fmt"

// =============================================================================
// B001: Unmatched Brace / Unclosed Block
// =============================================================================
//
// Scans the raw token stream (not the AST) for brace imbalance:
//
//   Unclosed:  { opened at line N never matched before EOF
//   Surplus:   } encountered when no { is on the stack
//
// Fires before tree-sitter parsing. When it fires, all other rules are
// suppressed for that file — the AST produced from an unbalanced file is
// unreliable.
//
// Odin-specific scanner behaviour:
//   - // single-line comments skip to \n
//   - /* ... */ block comments are NESTABLE (Odin allows /* /* */ */)
//   - "..." string literals with \" escape, no nesting
//   - `...` raw string literals (backtick), no escapes, no nesting
//   - '...' rune literals with \' escape
//   - { } inside any of the above are NOT counted
//
// Category: STRUCTURAL (error tier, always enabled)
// =============================================================================

BracePos :: struct {
    line, col: int,
}

// b001_check scans content for brace imbalance.
// Returns a (possibly empty) slice of Diagnostics. Caller must delete the slice.
b001_check :: proc(file_path: string, content: string) -> []Diagnostic {
    diags := make([dynamic]Diagnostic)
    stack := make([dynamic]BracePos)
    defer delete(stack)

    line := 1
    col  := 1
    i    := 0
    n    := len(content)

    for i < n {
        ch := content[i]

        // ── newline ──────────────────────────────────────────────────────────
        if ch == '\n' {
            line += 1
            col   = 1
            i    += 1
            continue
        }

        // ── single-line comment: // to end of line ───────────────────────────
        if ch == '/' && i+1 < n && content[i+1] == '/' {
            for i < n && content[i] != '\n' { i += 1 }
            continue
        }

        // ── block comment: /* ... */ (nestable) ──────────────────────────────
        if ch == '/' && i+1 < n && content[i+1] == '*' {
            depth := 1
            i    += 2
            col  += 2
            for i < n && depth > 0 {
                c := content[i]
                if c == '\n' {
                    line += 1; col = 1
                } else if c == '/' && i+1 < n && content[i+1] == '*' {
                    depth += 1; i += 1; col += 1
                } else if c == '*' && i+1 < n && content[i+1] == '/' {
                    depth -= 1; i += 1; col += 1
                } else {
                    col += 1
                }
                i += 1
            }
            continue
        }

        // ── double-quoted string literal: "..." with \" escape ───────────────
        if ch == '"' {
            i   += 1
            col += 1
            for i < n {
                c := content[i]
                if c == '"'  { i += 1; col += 1; break }
                if c == '\\' { i += 1; col += 1 } // skip escaped char
                if c == '\n' { line += 1; col = 1 } else { col += 1 }
                i += 1
            }
            continue
        }

        // ── raw string literal: `...` no escapes ─────────────────────────────
        if ch == '`' {
            i   += 1
            col += 1
            for i < n {
                c := content[i]
                if c == '`'  { i += 1; col += 1; break }
                if c == '\n' { line += 1; col = 1 } else { col += 1 }
                i += 1
            }
            continue
        }

        // ── rune literal: '...' with \' escape ───────────────────────────────
        if ch == '\'' {
            i   += 1
            col += 1
            for i < n {
                c := content[i]
                if c == '\''  { i += 1; col += 1; break }
                if c == '\\' { i += 1; col += 1 }
                if c == '\n' { line += 1; col = 1 } else { col += 1 }
                i += 1
            }
            continue
        }

        // ── open brace ───────────────────────────────────────────────────────
        if ch == '{' {
            append(&stack, BracePos{line, col})
            i   += 1
            col += 1
            continue
        }

        // ── close brace ──────────────────────────────────────────────────────
        if ch == '}' {
            if len(stack) == 0 {
                append(&diags, Diagnostic{
                    file      = file_path,
                    line      = line,
                    column    = col,
                    rule_id   = "B001",
                    tier      = "structural",
                    message   = fmt.aprintf(
                        "unexpected closing brace at line %d, col %d — no matching opening brace",
                        line, col,
                    ),
                    has_fix   = false,
                    diag_type = .VIOLATION,
                })
            } else {
                pop(&stack)
            }
            i   += 1
            col += 1
            continue
        }

        i   += 1
        col += 1
    }

    // Remaining stack entries are unclosed blocks.
    for pos in stack {
        append(&diags, Diagnostic{
            file      = file_path,
            line      = pos.line,
            column    = pos.col,
            rule_id   = "B001",
            tier      = "structural",
            message   = fmt.aprintf(
                "unclosed block opened at line %d, col %d — expected matching '}'",
                pos.line, pos.col,
            ),
            has_fix   = false,
            diag_type = .VIOLATION,
        })
    }

    return diags[:]
}
