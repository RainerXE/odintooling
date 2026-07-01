// rule_docs.odin — detailed rule documentation for `olt --explain <RULE>`.
// explain_rule returns a multi-line string with description, examples, and fix
// guidance for the requested rule ID; returns ("", false) for unknown IDs.
package core

import "core:fmt"

// =============================================================================
// Rule documentation — used by --explain <RULE_ID>
// =============================================================================

// explain_rule returns (documentation_string, true) for known rule IDs,
// ("", false) for unknown ones.
explain_rule :: proc(id: string) -> (string, bool) {
    switch id {
    case "B001": return B001_DOCS, true
    case "B002": return B002_DOCS, true
    case "C001": return C001_DOCS, true
    case "C002": return C002_DOCS, true
    case "C003": return C003_DOCS, true
    case "C007": return C007_DOCS, true
    case "C009": return C009_DOCS, true
    case "C010": return C010_DOCS, true
    case "C011": return C011_DOCS, true
    case "C012": return C012_DOCS, true
    case "C014": return C014_DOCS, true
    case "C015": return C015_DOCS, true
    case "C016": return C016_DOCS, true
    case "C017": return C017_DOCS, true
    case "C018": return C018_DOCS, true
    case "C019": return C019_DOCS, true
    case "C021": return C021_DOCS, true
    case "C022": return C022_DOCS, true
    case "C023": return C023_DOCS, true
    case "C025": return C025_DOCS, true
    case "C029": return C029_DOCS, true
    case "C031": return C031_DOCS, true
    case "C033": return C033_DOCS, true
    case "C034": return C034_DOCS, true
    case "C037": return C037_DOCS, true
    case "C101": return C101_DOCS, true
    case "C201": return C201_DOCS, true
    case "C202": return C202_DOCS, true
    case "C203": return C203_DOCS, true
    }
    return fmt.tprintf("Unknown rule '%s'. Run 'olt --list-rules' for available rules.\n", id), false
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

@(private)
B001_DOCS :: `
=============================================================================
B001 — Unmatched brace / unclosed block
Tier: structural
=============================================================================

WHAT IT DETECTS
  Brace imbalance in raw source before tree-sitter parsing: an opening '{'
  with no matching '}', or a surplus '}' with nothing on the stack.

WHY IT MATTERS
  An unbalanced file produces an unreliable AST. When B001 fires, all other
  rules are suppressed for that file until the syntax is fixed.

FIX
  Match every '{' with a '}' in the same scope. Check for missing braces in
  if/for/when blocks and procedure bodies.
`

@(private)
B002_DOCS :: `
=============================================================================
B002 — Package name inconsistent within directory
Tier: structural
=============================================================================

WHAT IT DETECTS
  .odin files in the same directory declaring different package names.
  The majority name wins; outlier files are flagged.

WHY IT MATTERS
  Odin requires all files in one directory to share the same package name.
  Mixed names are a compiler error and usually indicate a copy/paste mistake.

FIX
  Rename the outlier package declaration to match the directory majority.
  Exception: 'package foo_test' is valid alongside 'package foo'.
`

@(private)
C014_DOCS :: `
=============================================================================
C014 — Private procedure never called  [opt-in: dead_code domain]
Tier: dead code (INFO)
=============================================================================

WHAT IT DETECTS
  Procedures marked @(private) or @(private="file") with zero incoming call
  edges in the project code graph.

WHY IT MATTERS
  Unused private procs are safe dead-code candidates for deletion.

REQUIRES
  Build the graph first: olt src/ --export-symbols
  Enable in olt.toml: [domains] dead_code = true

FIX
  Delete the unused proc, or call it if it is still needed.
`

@(private)
C015_DOCS :: `
=============================================================================
C015 — Private constant never referenced  [opt-in: dead_code domain]
Tier: dead code (INFO)
=============================================================================

WHAT IT DETECTS
  Unexported constants with no references anywhere in the project graph.

REQUIRES
  olt src/ --export-symbols and [domains] dead_code = true in olt.toml.

FIX
  Remove the unused constant or wire it into the codebase.
`

@(private)
C016_DOCS :: `
=============================================================================
C016 — Local variable name must be snake_case
Tier: style (default on)
=============================================================================

WHAT IT DETECTS
  Local variable declarations whose names are not snake_case.

WHY IT MATTERS
  Odin style uses snake_case for locals, keeping them visually distinct from
  PascalCase types and exported symbols.

FIX
  Rename the variable to snake_case (e.g. myVar → my_var).
  Disable in olt.toml: [naming] c016 = false
`

@(private)
C017_DOCS :: `
=============================================================================
C017 — Package-level variable name must be camelCase  [opt-in]
Tier: style
=============================================================================

WHAT IT DETECTS
  Module-level variables whose names are not camelCase.

ENABLE
  [naming] c017 = true in olt.toml

FIX
  Rename to camelCase (e.g. my_counter → myCounter).
`

@(private)
C018_DOCS :: `
=============================================================================
C018 — Procedure name must reflect @(private) visibility  [opt-in]
Tier: style
=============================================================================

WHAT IT DETECTS
  Private procedures whose names look exported (PascalCase) or exported
  procedures whose names look private (leading underscore / all lower).

ENABLE
  [naming] c018 = true in olt.toml

FIX
  Align naming with visibility: exported → PascalCase, private → snake_case.
`

@(private)
C019_DOCS :: `
=============================================================================
C019 — Type marker suffix conventions  [opt-in]
Tier: style
=============================================================================

WHAT IT DETECTS
  Variables whose names do not carry the suffix expected for their type
  (e.g. _ptr for pointers, _slice for slices, _map for maps, _alloc for
  allocators).

ENABLE
  [naming] c019 = true in olt.toml

FIX
  Append the required suffix (player_ptr, items_slice, tracking_alloc, etc.).
  Suppress: // olt:ignore C019
`

@(private)
C101_DOCS :: `
=============================================================================
C101 — context.allocator assigned without defer restore
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Assignments to context.allocator or context.temp_allocator with no matching
  'defer context.allocator = <saved>' restore in the same procedure.

WHY IT MATTERS
  Mutating context.allocator without restoring it silently changes the
  allocator for all downstream code in the caller's scope after return.

FIRES:

    proc work() {
        context.allocator = my_alloc   // C101: no defer restore
        do_stuff()
    }

SILENT — correct pattern:

    proc work() {
        old := context.allocator
        context.allocator = my_alloc
        defer context.allocator = old
        do_stuff()
    }

FIX
  Save the old allocator and add 'defer context.allocator = old' immediately
  after the assignment.
`

@(private)
C021_DOCS :: `
=============================================================================
C021 — Go-style fmt call  [opt-in: go_migration domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Go-style fmt.Println, fmt.Printf, fmt.Sprintf, etc. — these do not exist
  in Odin and will not compile.

ENABLE
  [domains] go_migration = true in olt.toml

FIX
  Use Odin equivalents: fmt.println, fmt.printf, fmt.tprintf (temp),
  fmt.aprintf (owned), or return a proper error value instead of fmt.Errorf.
`

@(private)
C022_DOCS :: `
=============================================================================
C022 — Go-style 'for i, v := range' loop  [opt-in: go_migration domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Go-style range loops that use ':=' and 'range' — invalid Odin syntax.

ENABLE
  [domains] go_migration = true in olt.toml

FIX
  Use Odin iteration: 'for v in collection' or 'for v, i in collection'.
`

@(private)
C023_DOCS :: `
=============================================================================
C023 — C-style '*ptr' dereference  [opt-in: go_migration domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  C/Go-style pointer dereference with '*identifier' instead of Odin's 'ptr^'.

ENABLE
  [domains] go_migration = true in olt.toml

FIX
  Replace '*ptr' with 'ptr^'.
`

@(private)
C025_DOCS :: `
=============================================================================
C025 — append missing address-of  [opt-in: go_migration domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  append(slice, value) where Odin requires append(&slice, value) because
  append mutates the slice header in place.

ENABLE
  [domains] go_migration = true in olt.toml

FIX
  Pass a pointer to the slice: append(&my_slice, item)
`

@(private)
C029_DOCS :: `
=============================================================================
C029 — Stdlib allocation without defer delete  [opt-in: stdlib_safety domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Calls to known stdlib allocating procs whose results are not freed:
  strings.split/clone/join, fmt.aprintf, os.read_entire_file, etc.

ENABLE
  [domains] stdlib_safety = true in olt.toml

FIX
  Add 'defer delete(result)' immediately after the call, same as C001.
  Suppress: // olt:ignore C029
`

@(private)
C031_DOCS :: `
=============================================================================
C031 — panic() on expected runtime failure  (INFO)
Tier: style
=============================================================================

WHAT IT DETECTS
  'if !ok { panic(...) }' or 'if err != nil { panic(...) }' patterns where
  a proper error return would be more idiomatic Odin.

NOTE
  Emits INFO only — advisory, not blocking. Programming-error panics
  (unreachable, BUG, TODO, etc.) are not flagged.

FIX
  Return an error from the procedure instead of panicking on expected failures.
`

@(private)
C033_DOCS :: `
=============================================================================
C033 — strings.Builder not destroyed  [opt-in: stdlib_safety domain]
Tier: correctness
=============================================================================

WHAT IT DETECTS
  strings.builder_make() without a matching defer strings.builder_destroy().

ENABLE
  [domains] stdlib_safety = true in olt.toml

FIX
  Add 'defer strings.builder_destroy(&builder)' after builder_make().
  Suppress: // olt:ignore C033
`

@(private)
C034_DOCS :: `
=============================================================================
C034 — Unused blank index in for loop  (INFO + auto-fix)
Tier: style
=============================================================================

WHAT IT DETECTS
  'for v, _ in collection' where the index is discarded — the blank index
  is unnecessary in Odin.

FIX
  Use 'for v in collection'. Run 'olt --fix' to apply automatically.
`

@(private)
C037_DOCS :: `
=============================================================================
C037 — Trailing return in void procedure  (INFO + auto-fix)
Tier: style
=============================================================================

WHAT IT DETECTS
  A bare 'return' as the last statement of a procedure with no return value.

FIX
  Remove the redundant return. Run 'olt --fix' to apply automatically.
`

@(private)
C201_DOCS :: `
=============================================================================
C201 — Error return value ignored (unchecked result)
Tier: correctness
=============================================================================

WHAT IT DETECTS
  Bare call statements whose result is discarded, where the called procedure
  is known to return an error or bool success indicator.

WHY IT MATTERS
  Silently ignoring errors leads to undefined behaviour on failure paths.

FIRES:

    os.open("config.toml")          // C201: result discarded
    net.dial_tcp(...)               // C201

SILENT — correct patterns:

    f, err := os.open("config.toml")
    if err != nil { return err }
    defer os.close(f)

    if !do_thing() { return .Failed }

FIX
  Assign the result and handle the error, or use 'or_return' / 'or_else'.
  Suppress: // olt:ignore C201
`

@(private)
C202_DOCS :: `
=============================================================================
C202 — Switch on enum is not exhaustive
Tier: correctness
=============================================================================

WHAT IT DETECTS
  switch statements on an enum-typed variable that do not cover all enum
  members defined in the project graph.

REQUIRES
  Build the graph first: olt src/ --export-symbols

RESPECTED OPT-OUTS
  '#partial switch' — explicit incomplete switch
  'case _:'          — wildcard covers remaining values

FIX
  Add the missing enum cases, or use '#partial switch' if incompleteness is
  intentional.
`

@(private)
C203_DOCS :: `
=============================================================================
C203 — Defer in inner block fires before outer scope uses the handle
Tier: correctness
=============================================================================

WHAT IT DETECTS
  A resource handle assigned to an outer-scope variable (e.g. ctx.handle = f)
  while defer close(f) lives inside an inner if/for/when block. In Odin,
  defer fires at the END OF THE ENCLOSING BLOCK — not at procedure exit.

WHY IT MATTERS
  The handle becomes dangling in the outer scope after the inner block exits,
  but before the outer scope finishes using it.

FIX
  Move defer to the outer scope, or avoid storing the handle in outer
  variables until after the inner block completes.
  Suppress: // olt:ignore C203
`
