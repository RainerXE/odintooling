package core

import "core:fmt"
import "core:strings"

// =============================================================================
// C021 — Go-Style fmt Calls
// C022 — Go-Style Range Loop
// C023 — C-Style Pointer Dereference
// =============================================================================
// These rules catch top Go→Odin translation mistakes made by LLMs and humans
// migrating from Go.  All three produce compile errors in Odin; these rules
// give a more helpful message pointing at the correct Odin idiom.
//
// Implementation: text-line scanning (not tree-sitter) because the patterns
// involve syntax that tree-sitter-odin may not parse as valid nodes.
//
// Enabled via [domains] go_migration = true in olt.toml.
// OFF by default — pure Odin codebases don't need these.
// =============================================================================

// ---------------------------------------------------------------------------
// C021 — fmt.Println / fmt.Printf / fmt.Sprintf etc.
// ---------------------------------------------------------------------------

// Go fmt functions and their Odin equivalents.
C021_GO_FMT_CALLS :: [?][2]string{
	{"fmt.Println",  "fmt.println"},
	{"fmt.Print",    "fmt.print"},
	{"fmt.Printf",   "fmt.printf"},
	{"fmt.Fprintf",  "fmt.fprintf"},
	{"fmt.Fprintln", "fmt.fprintln"},
	{"fmt.Fprint",   "fmt.fprint"},
	// No direct Odin equivalent — suggest closest
	{"fmt.Sprintf",  "fmt.tprintf (temp) or fmt.aprintf (owned)"},
	{"fmt.Sprintln", "fmt.tprintf (temp) or fmt.aprintf (owned)"},
	{"fmt.Sprint",   "fmt.tprintf (temp) or fmt.aprintf (owned)"},
	{"fmt.Errorf",   "a return error enum/union value"},
}

c021_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1
		if !strings.contains(line, "fmt.") { continue }

		// Strip inline comments before checking
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }

		for pair in C021_GO_FMT_CALLS {
			go_name := pair[0]
			odin_eq := pair[1]
			if !strings.contains(code, go_name) { continue }

			// Word boundary: must be followed by (
			idx := strings.index(code, go_name)
			if idx < 0 { continue }
			after_end := idx + len(go_name)
			if after_end >= len(code) { continue }
			// Must be followed by ( to be a call
			rest := strings.trim_left(code[after_end:], " \t")
			if len(rest) == 0 || rest[0] != '(' { continue }
			// Must NOT be preceded by an ident char (no "myfmt.Println")
			if idx > 0 && is_ident_byte(code[idx-1]) { continue }

			if is_suppressed("C021", line_num, suppressions) { break }

			msg: string
			if strings.has_prefix(odin_eq, "a return") {
				msg = fmt.aprintf("'%s' does not exist in Odin — use %s", go_name, odin_eq)
			} else {
				msg = fmt.aprintf("'%s' does not exist in Odin — use '%s'", go_name, odin_eq)
			}

			append(&diags, Diagnostic{
				file      = file_path,
				line      = line_num,
				column    = idx + 1,
				rule_id   = "C021",
				tier      = "correctness",
				message   = msg,
				has_fix   = !strings.has_prefix(odin_eq, "a return") && !strings.contains(odin_eq, " or "),
				fix       = fmt.aprintf("Rename '%s' to '%s'", go_name, odin_eq),
				diag_type = .VIOLATION,
			})
			break // one diagnostic per line is enough
		}
	}
	return diags[:]
}

// ---------------------------------------------------------------------------
// C022 — Go-Style `for i, v := range slice`
// ---------------------------------------------------------------------------

c022_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1
		if !strings.contains(line, "range") { continue }

		// Strip inline comments
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }

		// Look for `for ... range ` (the Go for-range keyword pattern)
		// Odin has `0..<n` and `0..=n` range expressions but NOT the `range` keyword
		// Pattern: word-boundary `range` followed by an identifier (not a `.`)
		idx := strings.index(code, "range")
		if idx < 0 { continue }

		// Must be preceded by a word boundary (space or comma — part of for clause)
		if idx > 0 && is_ident_byte(code[idx-1]) { continue }

		// Must be followed by a space + identifier (not `0..<` style range expr)
		after := code[idx+len("range"):]
		if len(after) == 0 || after[0] != ' ' { continue }
		trimmed := strings.trim_left(after, " \t")
		if len(trimmed) == 0 { continue }
		// Must be followed by an ident char (slice/map variable, not a literal)
		if !is_ident_byte(trimmed[0]) { continue }

		// Must be inside a for statement context: check "for" appears before "range"
		before := strings.trim_left(code[:idx], " \t")
		if !strings.has_prefix(before, "for ") && !strings.contains(code[:idx], " for ") { continue }

		if is_suppressed("C022", line_num, suppressions) { continue }

		append(&diags, Diagnostic{
			file      = file_path,
			line      = line_num,
			column    = idx + 1,
			rule_id   = "C022",
			tier      = "correctness",
			message   = "Go-style 'for i, v := range' — Odin uses 'for v, i in collection' (value first, index second; no 'range' keyword)",
			has_fix   = false,
			fix       = "Replace with: for value, index in collection { ... }",
			diag_type = .VIOLATION,
		})
	}
	return diags[:]
}

// ---------------------------------------------------------------------------
// C023 — C-Style Pointer Dereference `*ptr`
// ---------------------------------------------------------------------------

c023_run :: proc(file_path: string, file_lines: []string) -> []Diagnostic {
	suppressions := collect_suppressions(1, len(file_lines), file_lines)
	defer delete(suppressions)
	diags := make([dynamic]Diagnostic)

	for line, line_idx in file_lines {
		line_num := line_idx + 1
		if !strings.contains(line, "*") { continue }

		// Strip inline comments
		code := line
		if ci := strings.index(line, "//"); ci >= 0 { code = line[:ci] }

		// Look for `= *identifier` or `:= *identifier` — C-style deref on assignment RHS
		// Exclude:
		//   - `[]*T` (slice of pointers — type annotation)
		//   - `a * b` (multiplication — surrounded by spaces or idents on both sides)
		//   - `**T` (double pointer type — two stars)
		//   - `^*T` (Odin pointer-to-pointer type)
		//   - `/*` (block comment start)

		offset := 0
		for offset < len(code) {
			star_pos := strings.index(code[offset:], "*")
			if star_pos < 0 { break }
			abs := offset + star_pos
			offset = abs + 1

			// The char after * must be an ident char (it's dereferencing a variable)
			if abs+1 >= len(code) || !is_ident_byte(code[abs+1]) { continue }

			// The char before * must indicate this is a dereference context:
			// `= *`, `:= *`, `( *`, `return *`, `, *`
			if abs == 0 { continue }
			prev := code[abs-1]
			// If preceded by ident char or digit — multiplication, skip
			if is_ident_byte(prev) || prev == ')' || prev == ']' { continue }
			// If preceded by / — block comment, skip
			if prev == '/' { continue }
			// If preceded by [ — slice type like []*T, skip
			if prev == '[' { continue }
			// If preceded by ^ — pointer-to-pointer ^*T, skip
			if prev == '^' { continue }
			// If preceded by another * — **T double pointer type, skip
			if prev == '*' { continue }

			// Only flag when clearly in a value context: after =, (, return, ,
			if prev != '=' && prev != '(' && prev != ',' && prev != ' ' && prev != '\t' { continue }

			// Double-check: if it's := or ==, also check the char before prev
			if prev == '=' && abs >= 2 {
				pp := code[abs-2]
				// := and == are not deref contexts
				if pp == ':' || pp == '=' || pp == '!' || pp == '<' || pp == '>' { continue }
			}

			if is_suppressed("C023", line_num, suppressions) { break }

			// Extract the identifier being dereferenced
			end := abs + 1
			for end < len(code) && is_ident_byte(code[end]) { end += 1 }
			var_name := code[abs+1 : end]

			append(&diags, Diagnostic{
				file      = file_path,
				line      = line_num,
				column    = abs + 1,
				rule_id   = "C023",
				tier      = "correctness",
				message   = fmt.aprintf(
					"C-style dereference '*%s' — Odin uses postfix '^': write '%s^' instead",
					var_name, var_name),
				has_fix   = true,
				fix       = fmt.aprintf("Replace '*%s' with '%s^'", var_name, var_name),
				diag_type = .VIOLATION,
			})
			break // one diagnostic per line
		}
	}
	return diags[:]
}
