// c001-COR-Memory.odin — C001: heap allocation without matching defer free.
// Uses the ASTNode walker to find make()/new() assignments that lack a defer delete()
// or defer free() in the same block scope, with owner-transfer and arena escape hatches.
package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C001: Allocation without matching defer free in same scope
// =============================================================================
//
// Detects calls to make() or new() where the result is assigned to a local
// variable that is never freed in the same block scope.
//
// Only the two built-in allocating functions are checked:
//   make()  — slices, maps, dynamic arrays, channels
//   new()   — single-value heap allocation
//
// User-defined functions whose names begin with "make" or "new" are NOT flagged
// because detection uses exact suffix matching: "make(" and "new(".
//
// ESCAPE HATCHES — the rule is silent when:
//   1. The variable is returned from the proc (ownership transferred to caller)
//   2. A matching defer free() / defer delete() exists in the same block
//   3. Any argument to make/new contains the word "allocator" — covers
//      runtime.default_allocator(), mem.arena_allocator(&x),
//      context.temp_allocator, context.allocator, and custom allocator vars.
//      Multi-line calls are scanned across all lines of the call expression.
//   4. context.allocator is assigned anywhere in the block (arena pattern).
//      Detected via both AST walk and source-line text scan.
//   5. context := context appears in the block (context-shadow arena pattern)
//   6. A manual free/delete call for the variable exists in the block
//   7. The enclosing proc is an initializer: name ends in _init, starts with
//      init_, or is exactly "init" — these procs allocate module-lifetime
//      state that is torn down at subsystem shutdown, not per-call.
//   8. An inline suppression comment is present (see below)
//
// SUPPRESSION — add to the allocation line or the line before:
//   buf := make([]u8, n)  // olt:ignore C001 caller owns this
//   // olt:ignore C001 intentional — arena-managed
//   buf := make([]u8, n)
//
// FILE EXCLUSIONS — automatically skipped paths:
//   /core/    /vendor/    /generated/    /fixtures/
//
// KNOWN LIMITATION:
//   Multi-variable declarations track only the first variable:
//     a, b := make([]int, 10), make([]int, 20)  — only 'a' is checked
//   Workaround: use separate declarations for each allocation.
// =============================================================================

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

C001ScopeContext :: struct {
    allocations:          [dynamic]AllocationInfo,
    defers:               [dynamic]DeferInfo,
    has_arena:            bool,
    returns_var:          map[string]bool,
    is_perf_critical:     bool,
}

AllocationInfo :: struct {
    var_name: string,
    line:     int,
    col:      int,
}

DeferInfo :: struct {
    freed_var: string,
}


// ---------------------------------------------------------------------------
// Rule entry points
// ---------------------------------------------------------------------------

// C001Rule returns the Rule struct for integration with the rule engine.
// main.odin calls c001_matcher directly for full multi-diagnostic reporting.
c001_rule :: proc() -> Rule {
    return Rule{
        id       = "C001",
        tier     = "correctness",
        category = .CORRECTNESS,  // Clippy-inspired categorization
        matcher  = c001_matcher_single,   // single-return shim for Rule interface
        message  = c001_message,
        fix_hint = c001_fix_hint,
    }
}

// c001_matcher_single is a shim that satisfies the Rule.matcher signature.
// It returns only the first diagnostic. Call c001_matcher directly for all.
c001_matcher_single :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    if should_exclude_file(file_path) do return Diagnostic{}
    diags := c001_matcher(file_path, node, {})
    return diags[0] if len(diags) > 0 else Diagnostic{}
}

// c001Matcher is the legacy entry point expected by main.odin
// Forwards to the new c001_matcher with empty file_lines
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic {
    return c001_matcher(file_path, node, {})
}

// c001_matcher is the primary entry point.
// file_lines may be passed in if the caller already has the file cached;
// when empty the file is read once here and shared with all child calls.
// show_ownership_hints: when true, emits INFO for allocations passed to
// a function call (potential ownership transfer). Set false via TOML
// [correctness] c001_ownership_hints = false to silence these hints.
c001_matcher :: proc(
    file_path:            string,
    node:                 ^ASTNode,
    file_lines:           []string,
    show_ownership_hints: bool = true,
) -> []Diagnostic {
    if should_exclude_file(file_path) do return {}

    // Read the file once at the top-level call; reuse in all recursive calls.
    lines := file_lines
    owned_content: []u8
    owned_lines:   []string

    if len(lines) == 0 {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil do return {}
        owned_content = content
        owned_lines   = strings.split(string(content), "\n")
        lines         = owned_lines
    }
    defer if owned_content != nil {
        delete(owned_lines)
        delete(owned_content)
    }

    all_diags: [dynamic]Diagnostic

    if node.node_type == "block" {
        for d in check_block(node, file_path, lines, show_ownership_hints) {
            append(&all_diags, d)
        }
    }

    for &child in node.children {
        for d in c001_matcher(file_path, &child, lines, show_ownership_hints) {
            append(&all_diags, d)
        }
    }

    return all_diags[:]
}


// ---------------------------------------------------------------------------
// Block-level analysis
// ---------------------------------------------------------------------------

check_block :: proc(
    block:                ^ASTNode,
    file_path:            string,
    file_lines:           []string,
    show_ownership_hints: bool = true,
) -> []Diagnostic {
    // Tier 2: init-and-hold heuristic.
    // Procs named *_init, init_*, or init allocate module-lifetime state.
    // No individual defer free is expected — the whole subsystem is torn down
    // together.  Suppress C001 for the entire block.
    proc_name := get_enclosing_proc_name(block, file_lines)
    if strings.has_suffix(proc_name, "_init") ||
       strings.has_prefix(proc_name, "init_") ||
       proc_name == "init" {
        return {}
    }

    ctx := C001ScopeContext{
        returns_var  = make(map[string]bool),
        allocations  = make([dynamic]AllocationInfo, 0, 8),
        defers       = make([dynamic]DeferInfo, 0, 8),
        is_perf_critical = is_perf_critical_block(block, file_lines),
    }

    // Single pass: classify every direct child of the block.
    for &child in block.children {
        if is_allocation_assignment(&child, file_lines) {
            var_name := extract_lhs_name(&child)
            if var_name == "" do continue

            // Skip if a non-default allocator is passed to make/new.
            call := find_direct_call_expression(&child)
            if call != nil && uses_non_default_allocator(call, file_lines) do continue

            // Skip if a manual cleanup exists anywhere in this block.
            if has_manual_cleanup(var_name, block) do continue

            append(&ctx.allocations, AllocationInfo{
                var_name = var_name,
                line     = child.start_line,
                col      = child.start_column,
            })
        }

        if is_defer_free(&child) {
            if freed := extract_freed_var_name(&child); freed != "" {
                append(&ctx.defers, DeferInfo{freed_var = freed})
            }
        }

        if changes_context_allocator(&child, file_lines) do ctx.has_arena = true

        if is_return_statement(&child) {
            extract_returned_vars(&child, &ctx.returns_var)
        }
    }

    // Entire block uses an arena — no individual frees needed.
    if ctx.has_arena do return {}

    // Build lookup sets.
    defer_frees := make(map[string]bool)
    for d in ctx.defers do defer_frees[d.freed_var] = true

    // Use centralized suppression system
    suppressions := collect_suppressions(block.start_line, block.end_line, file_lines)
    defer free_suppressions(suppressions)
    
    // Debug: Print suppression summary
    // summary := suppression_summary(suppressions)
    // fmt.println("DEBUG C001 Suppressions:", summary)

    diags: [dynamic]Diagnostic
    for alloc in ctx.allocations {
        // Suppression: comment on the same line or the line immediately before.
        if is_suppressed("C001", alloc.line, suppressions) do continue

        if alloc.var_name in ctx.returns_var do continue
        if alloc.var_name in defer_frees     do continue

        msg  := "Allocation without matching defer free in same scope"
        fix  := "Add 'defer free()' or 'defer delete()' immediately after this allocation"
        dtype := DiagnosticType.VIOLATION

        if ctx.is_perf_critical {
            msg   = "[C001] Allocation in performance-critical block — verify this is intentional"
            dtype = DiagnosticType.CONTEXTUAL
        }

        // Ownership-transfer hint: if the allocated variable is passed to a
        // function call in the same scope, it may be handing off ownership.
        // Downgrade to INFO so the user can verify rather than getting a false alarm.
        if dtype == .VIOLATION && show_ownership_hints {
            if callee := c001_find_callee_with_arg(alloc.var_name, block, file_lines, alloc.line); callee != "" {
                msg   = fmt.aprintf(
                    "Allocation '%s' may transfer ownership to '%s' — verify callee handles cleanup, or add 'defer delete(%s)'",
                    alloc.var_name, callee, alloc.var_name)
                fix   = fmt.aprintf(
                    "If '%s' takes ownership: add '// olt:ignore C001'. If not: add 'defer delete(%s)'",
                    callee, alloc.var_name)
                dtype = DiagnosticType.INFO
            }
        }

        append(&diags, Diagnostic{
            file      = file_path,
            line      = alloc.line,
            column    = alloc.col,
            rule_id   = "C001",
            tier      = "correctness",
            message   = msg,
            fix       = fix,
            has_fix   = true,
            diag_type = dtype,
        })
    }

    return diags[:]
}


// ---------------------------------------------------------------------------
// Detection helpers
// ---------------------------------------------------------------------------

// is_allocation_assignment returns true when the node is a local variable
// declaration or assignment whose RHS is a call to make() or new().
is_allocation_assignment :: proc(node: ^ASTNode, file_lines: []string) -> bool {
    if node.node_type != "short_var_decl" &&
       node.node_type != "assignment_statement" {
        return false
    }
    // Skip field assignments: thing.field = make(...)
    for &child in node.children {
        if child.node_type == "selector_expression" do return false
    }
    // Find a top-level call_expression and check whether its callee is make/new.
    for &child in node.children {
        if child.node_type != "call_expression" do continue
        if len(child.children) == 0 do continue
        callee := &child.children[0]
        if callee.start_line < 1 do continue
        idx := callee.start_line - 1
        if idx >= len(file_lines) do continue
        line := file_lines[idx]
        col  := callee.start_column - 1
        if col < 0 || col >= len(line) do continue
        rest := line[col:]
        if strings.has_prefix(rest, "make(") || strings.has_prefix(rest, "new(") {
            return true
        }
    }
    return false
}

// find_direct_call_expression returns the first top-level call_expression
// child without recursing into nested calls.
find_direct_call_expression :: proc(node: ^ASTNode) -> ^ASTNode {
    for &child in node.children {
        if child.node_type == "call_expression" do return &child
    }
    return nil
}

// uses_non_default_allocator returns true when the make/new call passes an
// explicit allocator argument.  Scans all source lines of the call expression
// (start_line..end_line) so multi-line make() calls are handled correctly.
//
// The first line is checked with has_allocator_arg (anchored to the make/new
// position).  Continuation lines have no make( prefix, so they are checked
// for the bare word "allocator" in the non-comment portion of the line.
uses_non_default_allocator :: proc(call_node: ^ASTNode, file_lines: []string) -> bool {
    start := call_node.start_line - 1
    end   := call_node.end_line   - 1
    if start < 0 || start >= len(file_lines) do return false
    if end < start { end = start }
    end = min(end, start + 20)          // cap: avoid pathological ranges
    end = min(end, len(file_lines) - 1)

    // First line: use full has_allocator_arg (anchored to make/new position).
    if has_allocator_arg(file_lines[start]) do return true

    // Continuation lines: check for "allocator" in non-comment code.
    for i in start + 1 ..= end {
        line := file_lines[i]
        code := line
        if comment := strings.index(line, "//"); comment >= 0 {
            code = line[:comment]
        }
        if strings.contains(code, "allocator") do return true
    }
    return false
}

// has_allocator_arg checks whether the argument list of make/new on this
// source line contains an allocator expression.  Only looks inside the
// parentheses, not at the rest of the line, to avoid false matches in
// comments or variable names.
//
// Matches any argument that contains the word "allocator" — this covers:
//   runtime.default_allocator(), mem.arena_allocator(&x),
//   context.temp_allocator, context.allocator, my_arena_alloc, etc.
has_allocator_arg :: proc(line: string) -> bool {
    make_pos := strings.index(line, "make(")
    new_pos  := strings.index(line, "new(")

    call_start := -1
    if make_pos >= 0 && new_pos >= 0 {
        call_start = make_pos + 4 if make_pos < new_pos else new_pos + 3
    } else if make_pos >= 0 {
        call_start = make_pos + 4
    } else if new_pos >= 0 {
        call_start = new_pos + 3
    }
    if call_start < 0 do return false

    args := line[call_start:]
    return strings.contains(args, "allocator")
}

// changes_context_allocator returns true when the node either:
//   - reassigns context.allocator  (assignment_statement)
//   - shadows context via context := context  (short_var_decl)
//
// Uses both AST inspection and a text-based fallback because the Odin
// tree-sitter grammar uses selector_expression (not field_expression) for
// context.allocator on the LHS, and the node type varies across grammar
// versions.
changes_context_allocator :: proc(node: ^ASTNode, file_lines: []string) -> bool {
    if node.node_type != "assignment_statement" &&
       node.node_type != "short_var_decl" {
        return false
    }

    // Detect context := context — both LHS and RHS must reference "context".
    if node.node_type == "short_var_decl" {
        context_count := 0
        for &child in node.children {
            if child.node_type == "identifier" && child.text == "context" {
                context_count += 1
            }
        }
        if context_count >= 2 do return true
        return false
    }

    // AST check: context.allocator = ... on the LHS.
    // Handles both field_expression and selector_expression grammar variants.
    for &child in node.children {
        is_field_node := child.node_type == "field_expression" ||
                         child.node_type == "selector_expression"
        if !is_field_node { continue }
        found_context := false
        for &gc in child.children {
            if gc.node_type == "identifier" && gc.text == "context" {
                found_context = true
            }
            if found_context &&
               (gc.node_type == "field_identifier" || gc.node_type == "identifier") &&
               gc.text == "allocator" {
                return true
            }
        }
    }

    // Text-based fallback: scan the source line for context.allocator assignment.
    // Catches cases where the AST node type doesn't match expectations.
    if node.start_line >= 1 && node.start_line <= len(file_lines) {
        line := file_lines[node.start_line - 1]
        // Strip trailing comment before checking, to avoid matching
        // commented-out code: "// context.allocator = ..."
        code := line
        if comment := strings.index(line, "//"); comment >= 0 {
            code = line[:comment]
        }
        if strings.contains(code, "context.allocator") do return true
    }
    return false
}


// ---------------------------------------------------------------------------
// Defer / free detection
// ---------------------------------------------------------------------------

// is_defer_free returns true when the node is a defer statement that calls
// free() or delete().
is_defer_free :: proc(node: ^ASTNode) -> bool {
    if node.node_type != "defer_statement" do return false
    for &child in node.children {
        if child.node_type != "call_expression" do continue
        for &gc in child.children {
            if gc.node_type == "identifier" &&
               (gc.text == "free" || gc.text == "delete") {
                return true
            }
        }
    }
    return false
}

// extract_freed_var_name returns the name of the variable passed to
// defer free(...) or defer delete(...).
extract_freed_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type != "call_expression" do continue
        found_callee := false
        for &gc in child.children {
            // Modern grammar: arguments are inside an argument_list node.
            if gc.node_type == "argument_list" {
                for &arg in gc.children {
                    if arg.node_type == "identifier" do return arg.text
                }
            }
            // Fallback: flat identifier children (older grammar).
            if gc.node_type == "identifier" {
                if !found_callee {
                    found_callee = true  // first identifier is the callee
                    continue
                }
                return gc.text  // second identifier is the argument
            }
        }
    }
    return ""
}

// is_free_call returns true when node is a call_expression that calls
// free() or delete() with var_name as its first argument.
is_free_call :: proc(node: ^ASTNode, var_name: string) -> bool {
    if node.node_type != "call_expression" do return false
    found_callee := false
    for &child in node.children {
        // argument_list wrapper (unused in current Odin grammar, kept for safety).
        if child.node_type == "argument_list" && found_callee {
            for &arg in child.children {
                if arg.node_type == "identifier" && arg.text == var_name {
                    return true
                }
            }
        }
        if child.node_type == "identifier" {
            if !found_callee {
                if child.text == "free" || child.text == "delete" {
                    found_callee = true
                }
            } else {
                // First identifier after the callee is the first argument.
                if child.text == var_name do return true
            }
        }
    }
    return false
}

// has_manual_cleanup returns true when a direct free/delete call for
// var_name exists anywhere in block (non-deferred, e.g. inside an if).
has_manual_cleanup :: proc(var_name: string, block: ^ASTNode) -> bool {
    if var_name == "" || var_name == "_" do return false
    for &child in block.children {
        // In the Odin tree-sitter grammar, call_expression is a direct child
        // of block — there is no expression_statement wrapper.
        if is_free_call(&child, var_name) do return true
        if child.node_type == "if_statement" &&
           contains_identifier(&child, var_name) {
            for &gc in child.children {
                if gc.node_type == "block" {
                    for &ggc in gc.children {
                        if is_free_call(&ggc, var_name) do return true
                    }
                }
            }
        }
    }
    return false
}


// ---------------------------------------------------------------------------
// Return-value tracking
// ---------------------------------------------------------------------------

is_return_statement :: proc(node: ^ASTNode) -> bool {
    return node.node_type == "return_statement"
}

// extract_returned_vars adds every identifier referenced in the return
// expression to result.  Recurses into sub-expressions so that
// `return buf[:n]` still captures "buf".
extract_returned_vars :: proc(node: ^ASTNode, result: ^map[string]bool) {
    for &child in node.children {
        if child.node_type == "identifier" && child.text != "" {
            result[child.text] = true
            continue  // identifiers have no meaningful children
        }
        extract_returned_vars(&child, result)
    }
}

// ---------------------------------------------------------------------------
// Suppression comment handling
// ---------------------------------------------------------------------------

// Note: Suppression functions have been moved to centralized suppression.odin module
// for reuse across all rules. The C001-specific suppression logic remains here
// for backward compatibility during the transition.

// ---------------------------------------------------------------------------
// Performance-critical block detection
// ---------------------------------------------------------------------------

// is_perf_critical_block returns true when the block (±5 lines) contains
// an explicit performance annotation comment.
is_perf_critical_block :: proc(block: ^ASTNode, file_lines: []string) -> bool {
    start := max(0, block.start_line - 5)
    end   := min(len(file_lines) - 1, block.end_line + 5)
    for i in start..=end {
        if i >= len(file_lines) do continue
        l := file_lines[i]
        if strings.contains(l, "// PERF:")       && !strings.contains(l, "// // PERF:") do return true
        if strings.contains(l, "// PERFORMANCE:") do return true
        if strings.contains(l, "// HOT_PATH")     do return true
        if strings.contains(l, "// HOT PATH")     do return true
        if strings.contains(l, "// FASTPATH")     do return true
        if strings.contains(l, "// OPTIMIZED")    do return true
    }
    return false
}


// ---------------------------------------------------------------------------
// AST utilities
// ---------------------------------------------------------------------------

// extract_lhs_name returns the first identifier on the left-hand side of
// an assignment or short variable declaration.
extract_lhs_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "identifier" do return child.text
    }
    return ""
}

// get_enclosing_proc_name scans backwards from the block's opening line to
// find the nearest "name :: proc" declaration and returns the proc name.
// Returns "" if no declaration is found within 5 lines.
get_enclosing_proc_name :: proc(block: ^ASTNode, file_lines: []string) -> string {
    // block.start_line is 1-based; convert to 0-indexed.
    // The opening brace is typically on the SAME line as "name :: proc() {",
    // so start the scan at the brace line itself (start_line - 1, 0-indexed).
    start := block.start_line - 1
    for i := start; i >= max(0, start - 5); i -= 1 {
        if i >= len(file_lines) do continue
        line := file_lines[i]
        decl_pos := strings.index(line, ":: proc")
        if decl_pos < 0 do continue
        // Extract the identifier to the left of "::"
        lhs := strings.trim_space(line[:decl_pos])
        // The name is the last whitespace-separated token on the lhs
        // (handles indented methods or table entries).
        last_space := strings.last_index(lhs, " ")
        if last_space >= 0 {
            lhs = lhs[last_space + 1:]
        }
        last_tab := strings.last_index(lhs, "\t")
        if last_tab >= 0 {
            lhs = lhs[last_tab + 1:]
        }
        return lhs
    }
    return ""
}

// contains_identifier recursively checks whether target appears anywhere
// in the subtree rooted at node.
contains_identifier :: proc(node: ^ASTNode, target: string) -> bool {
    if node.node_type == "identifier" && node.text == target do return true
    for &child in node.children {
        if contains_identifier(&child, target) do return true
    }
    return false
}

// ---------------------------------------------------------------------------
// File exclusion
// ---------------------------------------------------------------------------

// should_exclude_file returns true when file_path matches a directory that
// should be skipped entirely (stdlib, vendored deps, generated, test fixtures).
should_exclude_file :: proc(file_path: string) -> bool {
    segments := [][2]string{
        {"/core/",      "/core"},
        {"/vendor/",    "/vendor"},
        {"/generated/", "/generated"},
        {"/fixtures/",  "/fixtures"},
    }
    for seg in segments {
        if strings.contains(file_path, seg[0]) ||
           strings.has_suffix(file_path, seg[1]) {
            return true
        }
    }
    return false
}

// ---------------------------------------------------------------------------
// Rule message / fix hint
// ---------------------------------------------------------------------------

c001_message :: proc() -> string {
    return "Allocation without matching defer free in same scope"
}

c001_fix_hint :: proc() -> string {
    return "Add 'defer free()' or 'defer delete()' immediately after this allocation"
}

// ---------------------------------------------------------------------------
// Ownership-transfer detection
// ---------------------------------------------------------------------------

// c001_find_callee_with_arg scans block children after alloc_line for a
// function call that passes var_name as an argument. Returns the short
// callee name (e.g. "initStressTest") or "" if no such call is found.
@(private)
c001_find_callee_with_arg :: proc(
    var_name:   string,
    block:      ^ASTNode,
    file_lines: []string,
    alloc_line: int,
) -> string {
    if var_name == "" || var_name == "_" { return "" }
    for &child in block.children {
        if child.start_line <= alloc_line { continue }
        end := min(child.end_line, len(file_lines))
        for l := child.start_line; l <= end; l += 1 {
            if l < 1 || l > len(file_lines) { continue }
            line := file_lines[l-1]
            if !strings.contains(line, var_name) { continue }
            if !strings.contains(line, "(") { continue }
            // Skip lines where var_name is the assignment target.
            trimmed := strings.trim_left(line, " \t")
            if strings.has_prefix(trimmed, var_name) {
                rest := strings.trim_left(trimmed[len(var_name):], " \t")
                if len(rest) > 0 && (rest[0] == '=' || (len(rest) > 1 && rest[1] == '=')) {
                    continue
                }
            }
            if callee := c001_extract_callee(line, var_name); callee != "" {
                return callee
            }
        }
    }
    return ""
}

// c001_extract_callee returns the short function name of the call whose
// argument list contains var_name on the given source line.
// e.g. line="renderer.initStressTest(font, fallbacks)", var_name="fallbacks" → "initStressTest"
@(private)
c001_extract_callee :: proc(line: string, var_name: string) -> string {
    // Find var_name with word boundaries.
    var_pos := -1
    offset  := 0
    for offset < len(line) {
        idx := strings.index(line[offset:], var_name)
        if idx < 0 { break }
        abs := offset + idx
        before_ok := abs == 0 || !is_ident_byte(line[abs-1])
        after_end := abs + len(var_name)
        after_ok  := after_end >= len(line) || !is_ident_byte(line[after_end])
        if before_ok && after_ok { var_pos = abs; break }
        offset = abs + 1
    }
    if var_pos < 0 { return "" }

    // Find the opening '(' to the left of var_name.
    paren := -1
    depth := 0
    for i := var_pos - 1; i >= 0; i -= 1 {
        switch line[i] {
        case ')': depth += 1
        case '(':
            if depth == 0 { paren = i; break }
            depth -= 1
        }
        if paren >= 0 { break }
    }
    if paren < 0 { return "" }

    // Extract the identifier immediately before '('.
    fn_end := paren - 1
    for fn_end >= 0 && (line[fn_end] == ' ' || line[fn_end] == '\t') { fn_end -= 1 }
    if fn_end < 0 { return "" }

    fn_start := fn_end
    for fn_start > 0 && is_ident_byte(line[fn_start-1]) { fn_start -= 1 }

    name := line[fn_start : fn_end+1]
    if len(name) == 0 || !is_ident_byte(name[0]) { return "" }

    // Built-in and read-only functions never take ownership — filter them out
    // to avoid spurious "may transfer ownership to len/fmt/log" hints.
    switch name {
    // Built-in procs that read but never take ownership
    case "len", "cap", "size_of", "align_of", "offset_of",
         "assert", "panic", "print", "println", "printf",
         "eprintln", "eprintf", "fprintf", "fprintln",
         "append", "copy", "delete", "free",
         "transmute", "cast", "auto_cast",
         "min", "max", "abs", "clamp", "swizzle":
        return ""
    // Primitive type names used as casts: byte(x), u8(x), int(x), etc.
    case "byte", "u8", "u16", "u32", "u64", "u128",
         "i8", "i16", "i32", "i64", "i128",
         "f16", "f32", "f64", "f16le", "f16be",
         "f32le", "f32be", "f64le", "f64be",
         "int", "uint", "uintptr", "rawptr",
         "bool", "b8", "b16", "b32", "b64",
         "rune", "string", "cstring":
        return ""
    }
    return name
}

