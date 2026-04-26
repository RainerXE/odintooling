// c031-c034-c037-StyleInfo.odin — C031/C034/C037: INFO-tier style suggestions.
// C031 flags panic() on expected runtime failures; C034 flags for v,_ in (redundant blank
// index); C037 flags a trailing bare return at the end of a void procedure.
package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C031 — panic() for Expected Runtime Failures           (INFO)
// C034 — Unused Blank Index in For Loop                  (INFO + auto-fix)
// C037 — Trailing `return` in Void Procedure             (INFO + auto-fix)
// =============================================================================
//
// All three rules emit INFO (not VIOLATION): they suggest idiomatically better
// Odin but do not indicate a definite bug. They are enabled by default.
//
// C031: flags `if !ok { panic(...) }` or `if err != nil { panic(...) }`
//   patterns where a proper error-return would be more idiomatic.
//   Escape hatches: panic message contains BUG/TODO/unreachable; test files;
//   init procs; main proc.
//
// C034: flags `for v, _ in collection` where the blank index is unnecessary.
//   Auto-fix: drop `, _` to get `for v in collection`.
//
// C037: flags a bare `return` as the last statement of a void procedure.
//   Auto-fix: remove the redundant return.
// =============================================================================

// =============================================================================
// C031 — panic for expected runtime failures
// =============================================================================

// C031 message keywords that indicate a programming-error panic (NOT flagged).
// These panics are about invariant violations, not expected runtime failures.
C031_PROG_ERROR_KEYWORDS :: [?]string{
	"unimplemented",
	"unreachable",
	" BUG",
	"TODO",
	"should not",
	"should never",
	"impossible",
	"internal error",
	"invariant",
	"assertion",
}

// Error-condition prefixes that precede the panic call in the source.
C031_ERROR_CONDITIONS :: [?]string{
	"if !ok",
	"if !found",
	"if !success",
	"if !loaded",
	"if !valid",
	"if !open",
	"if err != nil",
	"if err != .None",
	"if parse_err",
}

c031_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	// Skip test fixtures and generated files.
	if strings.contains(file_path, "_test.odin") ||
	   strings.contains(file_path, "/tests/") ||
	   strings.contains(file_path, "/fixtures/") {
		return {}
	}

	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1

		// Quick filter: must contain panic(
		if !strings.contains(line, "panic(") { continue }

		// Strip comment portion.
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }
		if !strings.contains(code, "panic(") { continue }

		// Skip if the panic message indicates a programming error.
		if c031_is_prog_error_panic(code, file_lines, line_idx) { continue }

		// Skip if inside a proc named main, init, or test.
		if c031_in_exempt_proc(file_lines, line_idx) { continue }

		// Check: is this panic preceded (within 5 lines) by an error-condition check?
		if !c031_has_error_condition(file_lines, line_idx) { continue }

		if is_suppressed("C031", line_num, suppressions) { continue }

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line_num,
			column    = strings.index(code, "panic(") + 1,
			rule_id   = "C031",
			tier      = "correctness",
			message   = "panic() on expected runtime failure — consider returning an error value instead so callers can handle the failure gracefully",
			fix       = "Replace panic(...) with a proper error return: return {}, err_value",
			has_fix   = false,
			diag_type = .INFO,
		})
	}
	return diags[:]
}

@(private = "file")
c031_is_prog_error_panic :: proc(code: string, lines: []string, line_idx: int) -> bool {
	// Check the panic message text in the current and next 2 lines.
	end := min(line_idx + 3, len(lines))
	for i in line_idx..<end {
		for kw in C031_PROG_ERROR_KEYWORDS {
			if strings.contains(lines[i], kw) { return true }
		}
	}
	return false
}

@(private = "file")
c031_has_error_condition :: proc(lines: []string, line_idx: int) -> bool {
	// Look back up to 5 lines for a recognisable error-condition check.
	start := max(0, line_idx - 5)
	for i := line_idx; i >= start; i -= 1 {
		l := lines[i]
		if ci := strings.index(l, "//"); ci >= 0 { l = l[:ci] }
		for cond in C031_ERROR_CONDITIONS {
			if strings.contains(l, cond) { return true }
		}
	}
	return false
}

@(private = "file")
c031_in_exempt_proc :: proc(lines: []string, line_idx: int) -> bool {
	// Scan backwards to find the enclosing proc declaration.
	for i := line_idx; i >= 0; i -= 1 {
		l := lines[i]
		if !strings.contains(l, ":: proc") { continue }
		// Check for exempt proc names.
		if strings.contains(l, "main ::") { return true }
		if strings.contains(l, "_init ::") || strings.contains(l, "init_ ") { return true }
		if strings.contains(l, "_test ::") || strings.contains(l, "test_ ") { return true }
		return false  // First enclosing proc found and it's not exempt.
	}
	return false
}

// =============================================================================
// C034 — Unused blank index in for loop: `for v, _ in` → `for v in`
// =============================================================================

c034_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1

		// Must contain a for loop with blank index.
		if !strings.contains(line, "for ") { continue }
		if !strings.contains(line, ", _") { continue }
		if !strings.contains(line, " in ") { continue }

		// Strip comments.
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }

		for_pos := strings.index(code, "for ")
		if for_pos < 0 { continue }

		// Skip if `for` is inside a string literal (odd number of unescaped quotes before it).
		in_str := false
		for i := 0; i < for_pos; i += 1 {
			if code[i] == '"' && (i == 0 || code[i-1] != '\\') { in_str = !in_str }
		}
		if in_str { continue }

		after_for := code[for_pos + 4:]

		// Must contain `, _ in` or `, _ in ` pattern.
		blank_pos := strings.index(after_for, ", _ in")
		if blank_pos < 0 { continue }

		// Ensure the part before `, _ in` is an identifier (not a more complex expr).
		val_part := strings.trim(after_for[:blank_pos], " \t")
		if len(val_part) == 0 { continue }
		// Check word-boundary: the value should be a simple identifier.
		is_ident := true
		for ch in val_part {
			if !is_ident_byte(u8(ch)) && ch != '_' {
				is_ident = false
				break
			}
		}
		if !is_ident { continue }

		if is_suppressed("C034", line_num, suppressions) { continue }

		// Build the fix: remove `, _` from the for line.
		fixed, _ := strings.replace(code, ", _ in ", " in ", 1)
		fixed = strings.trim_right(fixed, " \t")

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line_num,
			column    = for_pos + 1,
			rule_id   = "C034",
			tier      = "style",
			message   = fmt.aprintf("blank index '_, _' is unnecessary — write 'for %s in ...' to iterate values only", val_part),
			fix       = fmt.aprintf("Change to: %s", strings.trim(fixed, " \t")),
			has_fix   = true,
			diag_type = .INFO,
		})
	}
	return diags[:]
}

// =============================================================================
// C037 — Trailing `return` in void procedure
// =============================================================================

c037_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	// Detect: bare `return` as the LAST statement of a void proc body.
	//
	// Reliable signal: the closing `}` that follows the return is at column 0
	// (indentation = 0), which marks the proc's body closing brace for all
	// top-level proc declarations.  Inner blocks (`if`, `for`) always close at
	// higher indentation, so they are not confused with the proc body.

	for line, line_idx in file_lines {
		line_num := line_idx + 1

		// Strip inline comments before checking for bare return.
		code_part := line
		if ci := strings.index(line, "//"); ci >= 0 { code_part = line[:ci] }
		trimmed := strings.trim(code_part, " \t")
		if trimmed != "return" { continue }

		// The return must be indented (not at column 0 — that would be odd).
		return_indent := len(line) - len(strings.trim_left(line, " \t"))
		if return_indent == 0 { continue }

		// Find the next non-blank, non-comment raw line.
		next_raw := c037_next_raw_line(file_lines, line_idx)
		// The closing brace must be at column 0 (proc body close).
		if next_raw == "" || !strings.has_prefix(next_raw, "}") { continue }
		if strings.trim(next_raw, " \t") != "}" { continue }

		// Skip if this proc has a return type.
		if !c037_is_void_proc(file_lines, line_idx) { continue }

		if is_suppressed("C037", line_num, suppressions) { continue }

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line_num,
			column    = strings.index(line, "return") + 1,
			rule_id   = "C037",
			tier      = "style",
			message   = "trailing 'return' at end of void procedure is redundant",
			fix       = "Remove the trailing 'return'",
			has_fix   = true,
			diag_type = .INFO,
		})
	}
	return diags[:]
}

@(private = "file")
c037_next_raw_line :: proc(lines: []string, from_idx: int) -> string {
	for i := from_idx + 1; i < len(lines); i += 1 {
		l := lines[i]
		lt := strings.trim(l, " \t")
		if lt == "" || strings.has_prefix(lt, "//") { continue }
		return l  // raw line with indentation preserved
	}
	return ""
}

@(private = "file")
c037_is_void_proc :: proc(lines: []string, from_idx: int) -> bool {
	for i := from_idx; i >= 0; i -= 1 {
		l := lines[i]
		if !strings.contains(l, ":: proc") && !strings.contains(l, ": proc") { continue }
		// If the proc signature contains `->`, it has a return type (not void).
		if strings.contains(l, "->") { return false }
		// Multi-line proc signatures: check the next few lines for `->`.
		end := min(i + 5, len(lines))
		for j in i+1..<end {
			jl := lines[j]
			if strings.contains(jl, "->") { return false }
			if strings.contains(jl, "{") { break } // reached body
		}
		return true
	}
	return false
}
