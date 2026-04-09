package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// C002: Double-free detection
// =============================================================================
//
// Detects when the same allocation is freed more than once via defer:
//
//   buf := make([]u8, 1024)
//   defer free(buf)   // first free — ok
//   defer free(buf)   // second free — C002 VIOLATION
//
// Only make() and new() allocations are tracked.
// Cross-scope double-frees are detected (allocation in outer scope,
// two defer frees at equal or deeper scopes).
//
// ESCAPE HATCHES — the rule is silent when:
//   1. No allocation record exists for the freed variable name
//   2. Each proc body is analysed independently (state resets at boundaries)
//
// KNOWN LIMITATIONS:
//   - mem.free() / mem.delete() qualified calls not detected (bare free/delete only)
//   - Proc literals (anonymous procs) trigger a context reset the same as named
//     procs; allocations in the enclosing scope are not visible inside them
//
// SUPPRESSION:
//   defer free(buf)  // odin-lint:ignore C002
//
// =============================================================================

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

C002AllocationInfo :: struct {
    var_name:    string,
    line:        int,
    col:         int,
    free_count:  int,   // number of defer frees seen for this allocation
    scope_level: int,   // scope depth when the allocation was recorded
}

C002AnalysisContext :: struct {
    allocations_map: map[string][dynamic]C002AllocationInfo,
    current_scope:   int,
    scope_stack:     [dynamic]int,  // stores block start_line for each entered scope
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// create_c002_context returns an initialised analysis context.
// Must be paired with destroy_c002_context when analysis is complete.
create_c002_context :: proc() -> C002AnalysisContext {
    return C002AnalysisContext{
        allocations_map = make(map[string][dynamic]C002AllocationInfo),
        current_scope   = 0,
        scope_stack     = make([dynamic]int),
    }
}

// destroy_c002_context frees all memory owned by the context.
destroy_c002_context :: proc(ctx: ^C002AnalysisContext) {
    for _, &v in ctx.allocations_map do delete(v)
    delete(ctx.allocations_map)
    delete(ctx.scope_stack)
}

@(private)
reset_c002_context :: proc(ctx: ^C002AnalysisContext) {
    for _, &v in ctx.allocations_map do delete(v)
    delete(ctx.allocations_map)
    delete(ctx.scope_stack)
    ctx.allocations_map = make(map[string][dynamic]C002AllocationInfo)
    ctx.scope_stack     = make([dynamic]int)
    ctx.current_scope   = 0
}


// ---------------------------------------------------------------------------
// Rule entry point
// ---------------------------------------------------------------------------

// C002Rule returns the Rule struct.
// NOTE: c002Matcher has a different signature than Rule.matcher — it requires
// a context and file_lines parameter. Call c002Matcher directly from main.odin.
C002Rule :: proc() -> Rule {
    return Rule{
        id       = "C002",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = nil,        // called directly — see c002Matcher below
        message  = c002_message,
        fix_hint = c002_fix_hint,
    }
}

// c002Matcher is the primary entry point.
// file_lines may be passed when the caller already has the file cached;
// when nil the file is read once here and passed to all recursive calls.
//
// IMPORTANT: defer order for owned_content / owned_lines:
//   owned_lines elements are subslices of owned_content, so owned_lines must
//   be deleted (its slice header) BEFORE owned_content (the backing bytes).
//   The defer at function scope runs in LIFO order, so:
//     defer delete(owned_content)  ← registered first, runs second ✓
//     defer delete(owned_lines)    ← registered second, runs first ✓
c002Matcher :: proc(
    file_path:  string,
    node:       ^ASTNode,
    ctx:        ^C002AnalysisContext,
    file_lines: []string = {},
) -> []Diagnostic {
    lines := file_lines
    owned_content: []u8
    owned_lines:   []string

    // Read file once at the top-level call; reuse in all recursive calls.
    if len(lines) == 0 {
        content, err := os.read_entire_file_from_path(file_path, context.allocator)
        if err != nil do return {}
        owned_content = content
        owned_lines   = strings.split(string(content), "\n")
        lines         = owned_lines
    }
    // Defers at function scope — runs when c002Matcher returns, NOT when the
    // if-block exits. owned_lines freed first (LIFO), then owned_content.
    defer if owned_content != nil { delete(owned_lines);  delete(owned_content) }

    diagnostics: [dynamic]Diagnostic

    // -- Scope tracking -------------------------------------------------------
    is_block := node.node_type == "block"
    if is_block {
        append(&ctx.scope_stack, node.start_line)
        ctx.current_scope = len(ctx.scope_stack)
    }

    // -- Proc boundary: reset context to avoid cross-function bleed -----------
    is_proc := node.node_type == "proc_declaration" ||
               node.node_type == "proc_literal"
    if is_proc {
        reset_c002_context(ctx)
    }


    // -- Allocation detection -------------------------------------------------
    if node.node_type == "assignment_statement" ||
       node.node_type == "short_var_decl" {

        var_name := c002_extract_lhs_name(node)
        if var_name != "" {
            // Find the top-level call_expression on the RHS.
            call := c002_find_direct_call(node)
            if call != nil && c002_is_alloc_call(call, lines) {
                // Track this allocation.
                c002_mark_allocated(var_name, node.start_line, node.start_column,
                                    ctx.current_scope, ctx)
            } else if call == nil {
                // Pure reassignment (no call on RHS) — mark existing record.
                c002_mark_reassigned(var_name, ctx)
            }
        }
    }

    // -- Double-free detection ------------------------------------------------
    if freed_var := c002_extract_defer_free_target(node, lines); freed_var != "" {
        if freed_var in ctx.allocations_map {
            diag := c002_mark_freed(freed_var, node.start_line, node.start_column,
                                    ctx.current_scope, file_path, ctx)
            if diag.message != "" {
                append(&diagnostics, diag)
            }
        }
    }

    // -- Recurse into children ------------------------------------------------
    for &child in node.children {
        for d in c002Matcher(file_path, &child, ctx, lines) {
            if d.message != "" do append(&diagnostics, d)
        }
    }

    // -- Exit scope -----------------------------------------------------------
    if is_block && len(ctx.scope_stack) > 0 {
        pop(&ctx.scope_stack)
        ctx.current_scope = len(ctx.scope_stack)
    }

    return diagnostics[:]
}


// ---------------------------------------------------------------------------
// Allocation / free tracking
// ---------------------------------------------------------------------------

c002_mark_allocated :: proc(
    var_name:    string,
    line, col:   int,
    scope_level: int,
    ctx:         ^C002AnalysisContext,
) {
    if var_name not_in ctx.allocations_map {
        ctx.allocations_map[var_name] = make([dynamic]C002AllocationInfo)
    }
    existing := ctx.allocations_map[var_name]
    append(&existing, C002AllocationInfo{
        var_name    = var_name,
        line        = line,
        col         = col,
        free_count  = 0,
        scope_level = scope_level,
    })
    ctx.allocations_map[var_name] = existing
}

// c002_mark_reassigned marks the allocation at the current (or nearest outer)
// scope as reassigned. Only used for informational tracking; the reassignment
// diagnostic was removed because reslicing produces too many false positives.
c002_mark_reassigned :: proc(var_name: string, ctx: ^C002AnalysisContext) {
    // No-op in this version — reassignment tracking removed to reduce noise.
    // Kept as a stub so call sites compile without change.
}

// c002_mark_freed increments the free count for the innermost matching
// allocation and returns a Diagnostic if a double-free is detected.
// Uses fmt.aprintf (context.allocator) so the fix string outlives the call.
c002_mark_freed :: proc(
    var_name:    string,
    line, col:   int,
    scope_level: int,
    file_path:   string,
    ctx:         ^C002AnalysisContext,
) -> Diagnostic {
    existing, ok := ctx.allocations_map[var_name]
    if !ok || len(existing) == 0 do return Diagnostic{}

    // Find the innermost allocation whose scope is <= current scope.
    best := -1
    for i in 0..<len(existing) {
        if existing[i].scope_level <= scope_level {
            if best == -1 || existing[i].scope_level > existing[best].scope_level {
                best = i
            }
        }
    }
    if best < 0 do return Diagnostic{}

    existing[best].free_count += 1
    ctx.allocations_map[var_name] = existing

    if existing[best].free_count <= 1 do return Diagnostic{}

    // Double-free detected.
    fix_msg := fmt.aprintf(
        "Remove duplicate defer free — allocation at line %d col %d has been freed %d times",
        existing[best].line, existing[best].col, existing[best].free_count,
    )
    return Diagnostic{
        file      = file_path,
        line      = line,
        column    = col,
        rule_id   = "C002",
        tier      = "correctness",
        message   = "Multiple defer frees on the same allocation (double-free)",
        fix       = fix_msg,
        has_fix   = true,
        diag_type = .VIOLATION,
    }
}


// ---------------------------------------------------------------------------
// AST helpers — detection
// ---------------------------------------------------------------------------

// c002_extract_defer_free_target returns the variable name freed by a
// defer free(...) or defer delete(...) statement, or "" if not applicable.
// Combines is_defer_cleanup + extract_var_name into a single tree walk.
// Uses file_lines for callee detection (avoids unreliable node.text).
c002_extract_defer_free_target :: proc(node: ^ASTNode, lines: []string) -> string {
    if node.node_type != "defer_statement" do return ""
    for &child in node.children {
        if child.node_type != "call_expression" do continue
        found_free_callee := false
        for &gc in child.children {
            // Check callee identifier via file_lines (node.text may be empty).
            if gc.node_type == "identifier" && !found_free_callee {
                if c002_ident_matches(gc, lines, "free") ||
                   c002_ident_matches(gc, lines, "delete") {
                    found_free_callee = true
                }
                continue
            }
            // Extract the argument once we know the callee is free/delete.
            if found_free_callee {
                if gc.node_type == "argument_list" {
                    for &arg in gc.children {
                        if arg.node_type == "identifier" {
                            name := c002_extract_ident_text(arg, lines)
                            if name != "" do return name
                        }
                    }
                }
                if gc.node_type == "identifier" {
                    name := c002_extract_ident_text(gc, lines)
                    if name != "" do return name
                }
            }
        }
    }
    return ""
}

// c002_is_alloc_call returns true when call_node's callee is make() or new().
// Uses file_lines for reliable text extraction.
c002_is_alloc_call :: proc(call_node: ^ASTNode, lines: []string) -> bool {
    if len(call_node.children) == 0 do return false
    callee := &call_node.children[0]
    if callee.node_type != "identifier" do return false
    return c002_ident_matches(callee, lines, "make") ||
           c002_ident_matches(callee, lines, "new")
}

// c002_find_direct_call returns the first top-level call_expression child
// without recursing (avoids matching nested calls as the top-level allocation).
c002_find_direct_call :: proc(node: ^ASTNode) -> ^ASTNode {
    for &child in node.children {
        if child.node_type == "call_expression" do return &child
    }
    return nil
}

// c002_extract_lhs_name returns the plain variable name on the LHS.
// Returns "" for field assignments (thing.field) and index expressions (buf[i]).
c002_extract_lhs_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "selector_expression" ||
           child.node_type == "index_expression" {
            return ""
        }
        if child.node_type == "identifier" do return child.text
    }
    return ""
}


// ---------------------------------------------------------------------------
// Low-level text helpers (file_lines based — avoids node.text unreliability)
// ---------------------------------------------------------------------------

// c002_ident_matches returns true when the identifier node at its source
// position starts with the given keyword followed by a non-identifier char
// (e.g. "free(" but not "free_all").
c002_ident_matches :: proc(node: ^ASTNode, lines: []string, keyword: string) -> bool {
    if node.start_line < 1 do return false
    idx := node.start_line - 1
    if idx >= len(lines) do return false
    line := lines[idx]
    col  := node.start_column - 1
    if col < 0 || col >= len(line) do return false
    rest := line[col:]
    if !strings.has_prefix(rest, keyword) do return false
    // Ensure the match is a complete identifier (not a prefix of a longer name).
    after := len(keyword)
    if after < len(rest) {
        c := rest[after]
        if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') {
            return false  // part of a longer identifier
        }
    }
    return true
}

// c002_extract_ident_text extracts the identifier text from source using
// file_lines. Returns "" when position is out of range.
c002_extract_ident_text :: proc(node: ^ASTNode, lines: []string) -> string {
    if node.start_line < 1 do return ""
    idx := node.start_line - 1
    if idx >= len(lines) do return ""
    line := lines[idx]
    col  := node.start_column - 1
    if col < 0 || col >= len(line) do return ""
    rest := line[col:]
    end  := 0
    for end < len(rest) {
        c := rest[end]
        if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') {
            end += 1
        } else {
            break
        }
    }
    return rest[:end]
}

// ---------------------------------------------------------------------------
// Rule message / fix hint
// ---------------------------------------------------------------------------

c002_message :: proc() -> string {
    return "Multiple defer frees on the same allocation (double-free)"
}

c002_fix_hint :: proc() -> string {
    return "Remove the duplicate defer free — each allocation should be freed exactly once"
}

