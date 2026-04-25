package core

import "core:fmt"

// =============================================================================
// Rule documentation — used by --explain <RULE_ID>
// =============================================================================

// explain_rule returns (documentation_string, true) for known rule IDs,
// ("", false) for unknown ones.
explain_rule :: proc(id: string) -> (string, bool) {
    switch id {
    case "C001": return C001_DOCS, true
    case "C002": return C002_DOCS, true
    case "C003": return C003_DOCS, true
    case "C007": return C007_DOCS, true
    case "C009": return C009_DOCS, true
    case "C010": return C010_DOCS, true
    case "C011": return C011_DOCS, true
    case "C012": return C012_DOCS, true
    }
    return fmt.tprintf("Unknown rule '%s'. Run 'odin-lint --list-rules' for available rules.\n", id), false
}

@(private)
C001_DOCS :: `
=============================================================================
C001 — Memory allocation without matching defer free
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Calls to make(), new(), or allocator procs that have no matching
  defer free() / defer delete() in the same scope.

WHY IT MATTERS
  Odin uses manual memory management. Without a deferred cleanup, memory
  allocated in a procedure leaks every time that procedure is called.

FIRES — will produce a C001 violation:

    proc load_config() {
        buf := make([]u8, 1024)   // no defer delete(buf) → leak
        parse(buf)
    }

SILENT — correct pattern:

    proc load_config() {
        buf := make([]u8, 1024)
        defer delete(buf)         // paired cleanup
        parse(buf)
    }

ESCAPE HATCHES
  - Returning the allocation transfers ownership to the caller (no violation).
  - Add a suppression comment to silence a specific line:
      buf := make([]u8, 1024)  // olt:ignore C001 caller owns this

FIX
  Add 'defer delete(buf)' for slices/maps/dynamic arrays, or 'defer free(ptr)'
  for raw pointers, immediately after the allocation.
`

@(private)
C002_DOCS :: `
=============================================================================
C002 — Double-free or use-after-free
Tier: correctness
=============================================================================

WHAT IT DETECTS
  A variable that is freed (via free(), delete(), ts_*_delete(), etc.) more
  than once in the same scope, which is undefined behaviour.

WHY IT MATTERS
  Freeing memory twice corrupts the allocator's internal state and can lead
  to security vulnerabilities, crashes, or silent data corruption.

FIRES — will produce a C002 violation:

    proc cleanup(p: rawptr) {
        free(p)
        free(p)   // C002: double-free
    }

    proc cleanup2() {
        buf := make([]u8, 64)
        defer delete(buf)
        delete(buf)  // C002: explicit delete + defer delete = double-free
    }

SILENT — correct pattern:

    proc cleanup(p: rawptr) {
        free(p)   // freed exactly once
    }

FIX
  Remove the duplicate free. Use defer for the canonical cleanup and remove
  any explicit call that runs before it.
`

@(private)
C003_DOCS :: `
=============================================================================
C003 — Procedure name must be snake_case
Tier: style
=============================================================================

WHAT IT DETECTS
  Procedure declarations whose names start with an uppercase letter or
  contain uppercase letters in non-leading positions without the standard
  Odin naming convention.

WHY IT MATTERS
  The Odin style guide specifies snake_case for procedure names. Consistent
  naming makes code easier to read and grep.

FIRES:

    MyProc :: proc() { }          // C003: PascalCase
    DoSomething :: proc() { }     // C003: PascalCase

SILENT:

    my_proc :: proc() { }         // snake_case — correct
    do_something :: proc() { }    // snake_case — correct

FIX
  Rename the procedure to snake_case (e.g. MyProc → my_proc).
`

@(private)
C007_DOCS :: `
=============================================================================
C007 — Type name must be PascalCase
Tier: style
=============================================================================

WHAT IT DETECTS
  Struct, enum, and union declarations whose names do not start with an
  uppercase letter (PascalCase convention).

WHY IT MATTERS
  The Odin style guide specifies PascalCase for type names. This makes types
  visually distinct from variables and procedures at a glance.

FIRES:

    my_struct :: struct { x: int }    // C007: not PascalCase
    result_code :: enum { ok, err }   // C007: not PascalCase

SILENT:

    MyStruct :: struct { x: int }     // PascalCase — correct
    ResultCode :: enum { Ok, Err }    // PascalCase — correct

FIX
  Rename the type to PascalCase (e.g. my_struct → MyStruct).
`

@(private)
C009_DOCS :: `
=============================================================================
C009 — Deprecated import: core:os/old
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Import declarations that reference 'core:os/old', which was removed in
  the Odin dev-2026-04 release.

WHY IT MATTERS
  'core:os/old' no longer exists. Code importing it will fail to compile
  on current Odin builds.

FIRES:

    import "core:os/old"        // C009: deprecated package

SILENT:

    import "core:os"            // current OS package — correct

FIX
  Replace 'import "core:os/old"' with 'import "core:os"' and update any
  call sites that used the old API.
`

@(private)
C010_DOCS :: `
=============================================================================
C010 — Small_Array superseded by [dynamic; N]T
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Usage of 'core:container/small_array.Small_Array(N, T)', which is
  superseded by the built-in fixed-capacity dynamic array syntax '[dynamic; N]T'
  introduced in Odin dev-2026-04.

WHY IT MATTERS
  Small_Array is no longer maintained. The built-in '[dynamic; N]T' syntax
  is first-class, more composable, and avoids an external import.

FIRES:

    import sa "core:container/small_array"
    arr: sa.Small_Array(8, int)     // C010
    x := Small_Array(8, int){}      // C010

SILENT:

    arr: [dynamic; 8]int            // built-in fixed-cap array — correct

FIX
  Replace 'Small_Array(N, T)' with '[dynamic; N]T'.
  Example: 'Small_Array(8, int)' → '[dynamic; 8]int'
`

@(private)
C011_DOCS :: `
=============================================================================
C011 — FFI C resource allocated without paired cleanup
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Calls to ts_*_new() (tree-sitter resource constructors) that have no
  matching 'defer ts_*_delete(handle)' in the same scope.

WHY IT MATTERS
  Tree-sitter resources are heap-allocated C objects. Without a deferred
  delete, they leak every time the enclosing procedure is called.

FIRES:

    proc build_query(lang: rawptr) -> rawptr {
        cursor := ts_query_cursor_new()    // C011: no defer ts_query_cursor_delete
        ts_query_cursor_exec(cursor, ...)
        return cursor
    }

SILENT — correct patterns:

    proc run_query(lang: rawptr) {
        cursor := ts_query_cursor_new()
        defer ts_query_cursor_delete(cursor)  // paired cleanup
        ts_query_cursor_exec(cursor, ...)
    }

    // Returning the handle transfers ownership — no violation:
    proc make_parser() -> TSParser {
        p := ts_parser_new()
        return p   // caller is responsible for ts_parser_delete
    }

SUPPRESSION
    handle := ts_query_new(...)  // olt:ignore C011 handle stored in returned struct

FIX
  Add 'defer ts_*_delete(handle)' immediately after allocation.
  Recognised pairs: ts_query_new/ts_query_delete,
  ts_parser_new/ts_parser_delete, ts_query_cursor_new/ts_query_cursor_delete.
`

@(private)
C012_DOCS :: `
=============================================================================
C012 — Semantic ownership naming hints  [opt-in: --enable-c012]
Tier: style
=============================================================================

WHAT IT DETECTS
  Variables that hold owned heap memory, borrowed slices, or allocators
  whose names give no signal about their memory ownership role.

WHY IT MATTERS
  In Odin, ownership is managed manually. Encoding ownership in names
  reduces bugs and makes code reviews faster by making intent explicit.

SUB-RULES

  S1 — make/new allocations should have _owned suffix:
    buf := make([]u8, 1024)         // INFO: consider 'buf_owned'
    buf_owned := make([]u8, 1024)   // silent

  S2 — slice aliases should use _view or _borrowed suffix:
    header := buf[0:4]              // INFO: consider 'header_view'
    header_view := buf[0:4]         // silent

  S3 — allocator variables should have 'alloc' in the name:
    a := mem.tracking_allocator(...)   // INFO: consider 'tracking_alloc'
    tracking_alloc := ...              // silent

NOTE
  C012 emits INFO diagnostics only — they are advisory, not blocking.
  Enable with '--enable-c012' or '--rule C012'.
  Suppress individual hints with: // olt:ignore C012
`
