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
//   3. A non-default allocator is passed as an argument (arena, temp, custom)
//   4. context.allocator is reassigned in the same block (arena pattern)
//   5. context := context appears in the block (context-shadow arena pattern)
//   6. A manual free/delete call for the variable exists in the block
//   7. An inline suppression comment is present (see below)
//
// SUPPRESSION — add to the allocation line or the line before:
//   buf := make([]u8, n)  // odin-lint:ignore C001 caller owns this
//   // odin-lint:ignore C001 intentional — arena-managed
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
C001Rule :: proc() -> Rule {
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
c001_matcher :: proc(
    file_path:  string,
    node:       ^ASTNode,
    file_lines: []string,
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
        for d in check_block(node, file_path, lines) {
            append(&all_diags, d)
        }
    }

    for &child in node.children {
        for d in c001_matcher(file_path, &child, lines) {
            append(&all_diags, d)
        }
    }

    return all_diags[:]
}


// ---------------------------------------------------------------------------
// Block-level analysis
// ---------------------------------------------------------------------------

check_block :: proc(
    block:      ^ASTNode,
    file_path:  string,
    file_lines: []string,
) -> []Diagnostic {
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

        if changes_context_allocator(&child) do ctx.has_arena = true

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

// uses_non_default_allocator returns true when the make/new call on this line
// passes an explicit allocator argument.
uses_non_default_allocator :: proc(call_node: ^ASTNode, file_lines: []string) -> bool {
    idx := call_node.start_line - 1
    if idx < 0 || idx >= len(file_lines) do return false
    return has_allocator_arg(file_lines[idx])
}

// has_allocator_arg checks whether the argument list of make/new on this
// source line contains an allocator expression.  Only looks inside the
// parentheses, not at the rest of the line, to avoid false matches in
// comments or variable names.
has_allocator_arg :: proc(line: string) -> bool {
    make_pos := strings.index(line, "make(")
    new_pos  := strings.index(line, "new(")

    call_start := -1
    if make_pos >= 0 && new_pos >= 0 {
        if make_pos < new_pos {
            call_start = make_pos + 4
        } else {
            call_start = new_pos + 3
        }
    } else if make_pos >= 0 {
        call_start = make_pos + 4
    } else if new_pos >= 0 {
        call_start = new_pos + 3
    }
    if call_start < 0 do return false

    args := line[call_start:]
    return strings.contains(args, "temp_allocator") ||
           strings.contains(args, ".allocator")     ||  // context.allocator, arena.allocator
           strings.contains(args, "allocator)")         // named param at end
}

// changes_context_allocator returns true when the node either:
//   - reassigns context.allocator  (assignment_statement)
//   - shadows context via context := context  (short_var_decl)
changes_context_allocator :: proc(node: ^ASTNode) -> bool {
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

    // Detect context.allocator = ... on the LHS.
    for &child in node.children {
        if child.node_type != "field_expression" do continue
        found_context := false
        for &gc in child.children {
            if gc.node_type == "identifier" && gc.text == "context" {
                found_context = true
            }
            if found_context &&
               gc.node_type == "field_identifier" &&
               gc.text == "allocator" {
                return true
            }
        }
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
        if child.node_type == "identifier" &&
           (child.text == "free" || child.text == "delete") {
            found_callee = true
        }
        if child.node_type == "argument_list" && found_callee {
            for &arg in child.children {
                if arg.node_type == "identifier" && arg.text == var_name {
                    return true
                }
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
        if child.node_type == "expression_statement" {
            if is_free_call(&child, var_name) do return true
        }
        if child.node_type == "if_statement" &&
           contains_identifier(&child, var_name) {
            for &gc in child.children {
                if is_free_call(&gc, var_name) do return true
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

