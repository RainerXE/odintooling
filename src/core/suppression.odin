package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// SUPPRESSION SYSTEM - Centralized inline comment suppression handling
// =============================================================================
//
// Provides utilities for parsing and handling inline suppression comments
// that allow users to disable specific linting rules on individual lines.
//
// Suppression Format:
//   // olt:ignore RULE_ID [reason]
//   // odin-lint: ignore RULE_ID [reason]
//   // olt:ignore RULE_ID,ANOTHER_RULE [reason]
//
// Examples:
//   buf := make([]u8, n)  // olt:ignore C001 caller owns this
//   // olt:ignore C001,C002 intentional arena pattern
//   data := make([]int, 100)
// =============================================================================

// is_suppression_comment returns true when the line contains a suppression
// marker in any of the accepted forms.  Both "olt:ignore" (current) and
// "odin-lint:ignore" (legacy) are valid.
is_suppression_comment :: proc(text: string) -> bool {
    return strings.contains(text, "//olt:ignore")          ||
           strings.contains(text, "// olt:ignore")         ||
           strings.contains(text, "//olt: ignore")         ||
           strings.contains(text, "// olt: ignore")        ||
           // legacy: odin-lint:ignore — kept for backwards compatibility
           strings.contains(text, "//odin-lint:ignore")    ||
           strings.contains(text, "// odin-lint:ignore")   ||
           strings.contains(text, "//odin-lint: ignore")   ||
           strings.contains(text, "// odin-lint: ignore")  ||
           strings.contains(text, "//Odin-Lint:Ignore")    ||
           strings.contains(text, "// Odin-Lint:Ignore")
}

// extract_suppressed_rules parses a suppression comment and returns
// a slice of rule IDs that should be suppressed on that line.
// Returns empty slice if the comment is not a valid suppression.
extract_suppressed_rules :: proc(line: string) -> []string {
    result: [dynamic]string
    
    // Find the suppression marker by checking each possible format
    marker_pos := -1
    marker_len := 0
    
    // Check current (olt:ignore) and legacy (odin-lint:ignore) forms
    markers := [?]string{
        "//olt:ignore", "// olt:ignore", "//olt: ignore", "// olt: ignore",
        "//odin-lint:ignore", "// odin-lint:ignore",
        "//odin-lint: ignore", "// odin-lint: ignore",
        "//Odin-Lint:Ignore", "// Odin-Lint:Ignore",
    }
    for marker in markers {
        if idx := strings.index(line, marker); idx >= 0 {
            marker_pos = idx
            marker_len = len(marker)
            break
        }
    }
    
    if marker_pos == -1 do return result[:]
    
    // Extract the part after the marker
    after_marker := line[marker_pos + marker_len:]
    // Trim whitespace - Odin's strings.trim requires a cutset
    after_marker = strings.trim(after_marker, " \t\n\r")
    
    // Debug: Print what we extracted
    // fmt.println("DEBUG: after_marker =", after_marker)
    
    // Find rule IDs (comma-separated or space-separated)
    // Format: RULE_ID or RULE_ID reason or RULE_ID,RULE_ID2
    
    // First, find where the rule IDs end (either at space or end of string)
    // Look for the first space that's not part of a rule ID
    rule_end := len(after_marker)
    for i in 0..<len(after_marker) {
        if after_marker[i] == ' ' || after_marker[i] == '\t' {
            rule_end = i
            break
        }
    }
    
    // Extract the rule ID part
    rule_part := after_marker[0:rule_end]
    
    // Split by comma to handle multiple rule IDs
    rule_ids := strings.split(rule_part, ",")
    
    for &rid in rule_ids {
        // Trim whitespace from each rule ID
        rid = strings.trim(rid, " \t\n\r")
        if len(rid) > 0 {
            append_elem(&result, rid)
        }
    }
    
    return result[:]
}

// collect_suppressions builds a map of { line_number -> [rule_ids] } for every
// suppression comment found within the given line range.
// Returns a map where each key is a 1-indexed line number and the value is
// a slice of rule IDs suppressed on that line.
// Can optionally use custom prefixes from configuration.
collect_suppressions :: proc(
    start_line: int,
    end_line: int,
    file_lines: []string,
) -> map[int][]string {
    result := make(map[int][]string)
    
    // Ensure we don't go out of bounds
    actual_start := max(0, start_line - 1)  // Convert to 0-indexed
    actual_end := min(len(file_lines) - 1, end_line - 1)
    
    for i in actual_start..=actual_end {
        if i >= len(file_lines) do continue
        line := file_lines[i]
        
        if !is_suppression_comment(line) do continue
        
        // Extract suppressed rules for this line
        suppressed_rules := extract_suppressed_rules(line)
        if len(suppressed_rules) == 0 do continue
        
        // Store with 1-indexed line number to match ASTNode conventions
        result[i + 1] = suppressed_rules
    }
    
    return result
}

// is_suppressed returns true if the given rule_id is suppressed on the specified line
// or the line immediately before it (for multi-line statements).
is_suppressed :: proc(
    rule_id: string,
    line_number: int,
    suppressions: map[int][]string,
) -> bool {
    // Check the exact line
    if rules, ok := suppressions[line_number]; ok {
        for r in rules {
            if r == rule_id do return true
        }
    }
    
    // Check the line before (for multi-line statements)
    if rules, ok := suppressions[line_number - 1]; ok {
        for r in rules {
            if r == rule_id do return true
        }
    }
    
    return false
}

// suppression_summary generates a human-readable summary of all suppressions
// found in the file, useful for debugging and reporting.
suppression_summary :: proc(suppressions: map[int][]string) -> string {
    if len(suppressions) == 0 do return "No suppressions found"
    
    lines: [dynamic]string
    defer delete(lines)
    append_elem(&lines, "Suppression Summary:")

    sorted_lines: [dynamic]int
    defer delete(sorted_lines)
    for line_num, _ in suppressions {
        append_elem(&sorted_lines, line_num)
    }

    // Simple bubble sort for small arrays
    for i in 0..<len(sorted_lines) {
        for j in i+1..<len(sorted_lines) {
            if sorted_lines[i] > sorted_lines[j] {
                sorted_lines[i], sorted_lines[j] = sorted_lines[j], sorted_lines[i]
            }
        }
    }

    for line_num in sorted_lines {
        rules    := suppressions[line_num]
        rule_str := strings.join(rules, ", ")
        append_elem(&lines, fmt.tprintf("  Line %d: suppress %s", line_num, rule_str))
    }

    return strings.join(lines[:], "\n")
}