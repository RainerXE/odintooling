# odin-lint — Post-V7 Rule Addendum
*New rule proposals for after V7 stabilisation*
*Cross-referenced: LLM Guide Chapters 1–16 · V7.6 Analysis Scope Model*
*Date: April 2026*

Rules are grouped by implementation cost. Each entry gives the scope tag,
the detection approach, the primary source of the mistake (LLM / human / both),
and a ready-to-use SCM query sketch where applicable.

---

## Group 1 — Compile-Error Catchers
*These fire on code that will not compile. The compiler already catches them,
but odin-lint gives a better message and a fix hint before the compiler runs.
All file scope. All ON by default.*

---

### C021 — Go-Style fmt Calls
**Source:** LLM (Chapter 8, 15) | **Scope:** File | **Auto-fix:** Partial

`fmt.Println`, `fmt.Printf`, `fmt.Sprintf`, `fmt.Errorf` do not exist in Odin's
`core:fmt`. They are the top Go→Odin translation mistakes.

```scheme
(call_expression
  function: (selector_expression
    operand:  (identifier) @pkg  (#eq? @pkg "fmt")
    field:    (field_identifier) @fn
    (#match? @fn "^(Println|Printf|Sprintf|Errorf|Fprintf|Sprint|Sprintln|Fprintln)$")))
```

Fix map (auto-applicable):
- `fmt.Println` → `fmt.println`
- `fmt.Printf`  → `fmt.printf`

Fix map (suggest only — human must choose):
- `fmt.Sprintf` → `fmt.tprintf` (temp alloc) or `fmt.aprintf` (owned, must free)
- `fmt.Errorf`  → return enum error or union error type

---

### C022 — Go-Style Range Loop
**Source:** LLM (Chapter 4) | **Scope:** File | **Auto-fix:** YES

`for i, v := range slice` is Go syntax and does not compile in Odin.
The Odin form is `for v, i in slice` — value first, index second, reversed
from Go. This is one of the five most common LLM mistakes (Chapter 15).

```scheme
; Detects the `range` keyword appearing inside a for-loop header
(for_statement
  (range_clause) @go_range)
```

Message: "Go-style `for i, v := range` — use `for v, i in collection` (value first, index second in Odin)."

---

### C023 — C-Style Pointer Dereference
**Source:** LLM (Chapter 7) | **Scope:** File | **Auto-fix:** YES

`*ptr` for dereference is C/Go syntax. Odin uses postfix `^`: `ptr^`.
Unary `*` in Odin is not the dereference operator.

```scheme
(unary_expression
  operator: "*"
  operand:  (identifier) @name) @c_deref
```

Auto-fix: `*name` → `name^`

---

### C024 — `errors` Package Import
**Source:** LLM (Chapter 16) | **Scope:** File | **Auto-fix:** NO

The `errors` package does not exist in Odin. `errors.New()` is Go. The
`--explain` output should show all three Odin error patterns (bool,
enum, union) with examples from Chapter 16.

```scheme
(import_declaration
  path: (interpreted_string_literal) @p (#eq? @p "\"errors\""))
```

---

### C025 — `append(slice, v)` Without Address-Of
**Source:** LLM + Human (Chapter 14) | **Scope:** File | **Auto-fix:** YES

In Go, `append` returns a new slice: `slice = append(slice, v)`.
In Odin, `append` takes a pointer and mutates in place: `append(&slice, v)`.
LLMs almost always write the Go form which either fails to compile or
silently does nothing (if the slice is passed by value).

```scheme
(call_expression
  function: (identifier) @fn (#eq? @fn "append")
  arguments: (argument_list
    (identifier) @slice_arg   ; first arg is identifier, not address-of
    .)) @wrong_append
; Refine: fire only when @slice_arg is NOT preceded by &
```

Auto-fix: `append(slice, v)` → `append(&slice, v)`

---

### C026 — `go my_proc()` Goroutine Syntax
**Source:** LLM (Chapter 13) | **Scope:** File | **Auto-fix:** NO

`go f()` does not exist in Odin. Goroutines do not exist. The correct
approach is `core:thread`. This is a compile error but a lint rule can
point at the right API.

```scheme
; "go" followed by a call_expression — Go goroutine syntax
; In tree-sitter-odin this may parse as a labelled expression or error node
(go_statement) @goroutine
```

Message: "Goroutines do not exist in Odin. Use `thread.create(my_proc)` + `thread.start(t)` from `core:thread`."

---

### C027 — Channel Syntax `make(chan T)` / `<-`
**Source:** LLM (Chapter 13) | **Scope:** File | **Auto-fix:** NO

Channels do not exist in Odin. `make(chan int)` and the `<-` operator are
Go-only. `core:sync` provides mutexes and condition variables.

```scheme
; make(chan ...) — channel creation
(call_expression
  function: (identifier) @fn (#eq? @fn "make")
  arguments: (argument_list
    (channel_type) @chan_type))
```

---

## Group 2 — Wrong-Behaviour Catchers
*These compile but produce incorrect or dangerous results.
Higher value than Group 1 because the compiler does not catch them.*

---

### C028 — `fmt.tprintf` Result Stored Past Temp Scope
**Source:** Human + LLM (Chapter 6, 8) | **Scope:** File | **Tier:** CONTEXTUAL

`fmt.tprintf` allocates on `context.temp_allocator`. Storing its result in a
struct field, returning it, or appending it to a `[dynamic]string` without
cloning first creates a dangling reference when `free_all(context.temp_allocator)`
is called.

Detection heuristic (file scope — no type info):
- `fmt.tprintf(...)` assigned to a variable
- That variable is then assigned to a struct field (`x.field = var`) or returned

```scheme
; Capture tprintf results
(short_var_decl
  (identifier_list (identifier) @var)
  (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier) @pkg (#eq? @pkg "fmt")
        field:   (field_identifier) @fn (#eq? @fn "tprintf"))))) @tprintf_assign
```

Post-capture logic: if `@var` appears as RHS of a field assignment or in a
return statement within the same block, fire CONTEXTUAL.

Message: "`fmt.tprintf` result stored past temp allocator scope — use `fmt.aprintf` and `defer delete(...)`, or `strings.clone()`."

---

### C029 — `strings.split` Result Not Freed
**Source:** Human + LLM (Chapter 8) | **Scope:** File | **Tier:** VIOLATION

`strings.split` allocates a `[]string` that must be freed with `delete(parts)`.
This is the string equivalent of C001. LLMs frequently call `strings.split`
without a matching `defer delete`. 

This is an extension of C001's allocation detection to known stdlib allocating
procedures. Implemented by extending `memory_safety.scm` with a `known_allocators`
pattern list:

```scheme
; Known stdlib procs that return owned slices / strings
(short_var_decl
  (identifier_list (identifier) @var)
  (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier) @pkg
        field:   (field_identifier) @fn
        (#match? @fn "^(split|split_n|split_after|split_after_n|fields|fields_proc|clone|clone_to_cstring|join|concatenate|repeat)$")
        (#eq? @pkg "strings"))))) @strings_alloc
```

Same escape-hatch logic as C001: if a `defer delete(@var)` exists in the same
block, suppress. If `@var` is returned, suppress.

---

### C030 — `or_return` Used Outside a Proc Returning Error/Bool
**Source:** LLM (Chapter 16) | **Scope:** File | **Tier:** correctness

`or_return` propagates the error/false value up. If the enclosing proc returns
only a single non-bool/non-union value, `or_return` either fails to compile or
silently swallows the error. LLMs copy the `or_return` pattern without checking
the enclosing proc's return signature.

Detection: find `or_return` expressions in procs whose return type does not
include a bool or union as the final return value.

This needs the enclosing proc declaration to be visible — requires walking
up the AST from the `or_return` node to its containing `proc_declaration`.
File scope. No type resolution needed.

---

### C031 — Panic Used for Expected Runtime Failures
**Source:** LLM + Human (Chapter 16) | **Scope:** File | **Tier:** CONTEXTUAL (INFO)

`panic(...)` is for programmer contract violations, not runtime conditions
like missing files or bad input. LLMs (and novice humans) write:

```odin
data, ok := os.read_entire_file(path)
if !ok { panic("file not found") }  // WRONG
```

Detection heuristic: `panic(...)` call immediately following a `!ok` or
`== false` check on a variable that was assigned from an I/O or parsing call.

```scheme
(if_statement
  condition: (unary_expression operator: "!" operand: (identifier) @ok_var)
  body: (block
    (expression_statement
      (call_expression
        function: (identifier) @fn (#eq? @fn "panic"))))) @panic_on_ok
```

Message: "`panic` used for expected failure — return an error value instead. `panic` is for programmer contract violations only."
Tier: INFO (not all panics on !ok are wrong — e.g. in tests or init code).

---

### C032 — `defer` Inside a For Loop
**Source:** Human (our own lessons learned) | **Scope:** File | **Tier:** VIOLATION

`defer` in Odin scopes to the **enclosing procedure**, not the enclosing block.
Inside a `for` loop, every iteration allocates but nothing is freed until the
proc returns. This is among the most dangerous Odin memory mistakes because it
**looks correct** to anyone familiar with other languages.

```scheme
; defer statement that is a direct child of a for-loop body
(for_statement
  body: (block
    (defer_statement) @defer_in_loop))
```

Escape hatch: suppress if the defer frees a variable declared outside the loop
(legitimate use of defer-in-loop: `defer wg.done()` on a wait group).

Message: "`defer` inside a `for` loop runs when the **procedure** exits, not each iteration. Use an explicit `free()`/`delete()` at the end of the loop body."

This is arguably the highest-value rule in this entire addendum — it silently
leaks memory on every iteration and nothing in the existing infrastructure catches it.

---

### C033 — `strings.Builder` Not Destroyed
**Source:** Human + LLM (Chapter 8) | **Scope:** File | **Tier:** VIOLATION

`strings.builder_init(&b)` allocates internal state that must be released with
`strings.builder_destroy(&b)`. This is identical to the C001 pattern but for a
specific struct type.

```scheme
(call_expression
  function: (selector_expression
    operand: (identifier) @pkg (#eq? @pkg "strings")
    field:   (field_identifier) @fn (#eq? @fn "builder_init")))
```

Post-capture: check that a `defer strings.builder_destroy(&b)` exists in the
same block. If not, fire.

---

## Group 3 — Semantic / Style (CONTEXTUAL / INFO)
*These are not bugs but common anti-patterns. OFF by default or INFO tier.*

---

### C034 — `for v, _ in collection` — Unused Index Blank
**Source:** Human | **Scope:** File | **Tier:** INFO

`for v, _ in collection` — the blank `_` for the index is redundant; `for v in collection`
is cleaner. Small cleanup rule.

```scheme
(for_statement
  (in_clause
    left: (identifier_list (identifier) @val (blank_identifier) @blank)
    right: (_))) @unused_index_blank
```

Auto-fix: `for v, _ in c` → `for v in c`

---

### C035 — `switch` on Enum Without `case:` Fallback
**Source:** Human | **Scope:** File | **Tier:** CONTEXTUAL
*Note: Full version requires type info (M6). File-scope heuristic below.*

A `switch` on an enum value that has no `case:` fallback is a latent bug —
adding a new enum variant silently falls through with no handling.

File-scope heuristic (no type info): flag `switch` statements with
enum-style `.Variant` case labels that have no bare `case:` clause.

```scheme
(switch_statement
  body: (switch_body)) @switch_no_default
; Post-capture: check switch_body has no (case_clause) with empty expression list
```

Full version at M6: OLS resolves the switched type to an enum and compares
covered cases against the enum's member list — this becomes C202 (already
in the V7 plan).

---

### C036 — Magic Numbers in Allocation Sizes
**Source:** Human | **Scope:** File | **Tier:** INFO (opt-in)

`make([]u8, 65536)` with a bare integer literal in the size position is a
common readability issue. Constant or named size is preferred.

```scheme
(call_expression
  function: (identifier) @fn (#match? @fn "^(make|new)$")
  arguments: (argument_list
    (_)
    (integer_literal) @magic_size)) @magic_alloc_size
; Fire only when @magic_size > configurable threshold (default: 256)
```

Config key: `[rules.C036] min_threshold = 256`

---

### C037 — Unnecessary `return` at End of Void Proc
**Source:** LLM (Go habit) | **Scope:** File | **Tier:** INFO

In Odin (as in most languages), a bare `return` at the end of a void proc is
unnecessary. LLMs trained on Go add it habitually.

```scheme
(procedure_declaration
  ; proc with no return type
  body: (block
    .
    (return_statement) @trailing_return .)) @void_trailing_return
; The . before and after anchor to end-of-block position
```

Auto-fix: delete the trailing `return`.

---

## Group 4 — Package / Project Scope
*Require multi-file context. Post-M5 work.*

---

### P001 — Inconsistent Error Return Convention Within Package
**Source:** Human | **Scope:** Package | **Tier:** CONTEXTUAL

When one proc in a package returns `(T, bool)` for error and another returns
`(T, MyError)`, the package has inconsistent error conventions. Not a bug but
a strong code smell for library code.

Detection: compare all top-level proc return types in the package. If more than
one distinct error pattern is used (bool vs enum vs union) and no pattern
dominates >80%, fire CONTEXTUAL.

Requires the PackageContext struct (Scope 2).

---

### P002 — Exported Proc Without Doc Comment
**Source:** Human | **Scope:** Package | **Tier:** INFO (opt-in)

Public procs (no `@(private)` tag) without a preceding line comment are
undocumented API surface. Useful for library authors.

```scheme
(procedure_declaration
  ; no @(private) attribute
  ; not preceded by a comment node
  name: (identifier) @proc_name) @undocumented_proc
; Post-capture: check the node preceding @proc_name is not a (comment)
```

Config: `[domains] library_mode = true` to enable P002 automatically.

---

## Implementation Priority Order

| Rule | Group | Value | Cost | Do First? |
|------|-------|-------|------|-----------|
| C032 | 2 | 🔴 Critical | Low | YES — defer-in-loop, unique to Odin |
| C029 | 2 | 🔴 High | Low | YES — extends C001 infrastructure |
| C028 | 2 | 🟠 High | Medium | YES — tprintf temp scope escape |
| C021 | 1 | 🟠 High | Low | YES — most common LLM mistake |
| C022 | 1 | 🟠 High | Low | YES — range loop, LLM top-5 |
| C023 | 1 | 🟠 High | Low | YES — ptr deref, LLM top-5 |
| C025 | 1 | 🟠 High | Low | YES — append without & |
| C033 | 2 | 🟡 Medium | Low | After C029 (same pattern) |
| C030 | 2 | 🟡 Medium | Medium | After scope-walk infrastructure |
| C031 | 2 | 🟡 Medium | Low | INFO — low urgency |
| C024 | 1 | 🟡 Medium | Low | Compile error — lower urgency |
| C026 | 1 | 🟡 Medium | Low | Compile error — lower urgency |
| C027 | 1 | 🟡 Medium | Low | Compile error — lower urgency |
| C035 | 3 | 🟡 Medium | Low | C202 in M6 is the full version |
| C034 | 3 | 🟢 Low | Low | Cleanup rule |
| C036 | 3 | 🟢 Low | Low | Opt-in only |
| C037 | 3 | 🟢 Low | Low | INFO / auto-fix |
| P001 | 4 | 🟡 Medium | Medium | Post-M5 |
| P002 | 4 | 🟢 Low | Low | Post-M5, library mode only |

**The single highest-priority rule is C032 (defer in for loop).** It detects
a memory bug that is unique to Odin, invisible to the compiler, silent at
runtime until memory pressure builds, and extremely easy to accidentally
write. No equivalent rule currently exists in the V7.6 plan.

**C029 (strings.split not freed)** is a natural extension of C001 — same
infrastructure, same logic, just an extended list of known allocating procs.
Can be implemented as a configuration option within C001 rather than a
separate rule: `[rules.C001] track_stdlib_allocators = true`.

---

*Status: PROPOSED — for implementation after V7 stabilisation*
*Prerequisite: Gate 3 complete (SCM query engine + C001–C011 stable)*
*Scope tags follow the Analysis Scope Model in V7.6 Section 14*

---

## Appendix A — Known Stdlib Allocating Procedures (for C029 extension)

These procedures all return heap-allocated memory that the caller must free.
C029 / the `track_stdlib_allocators` C001 extension should detect all of them.
Grouped by package.

### `core:strings`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `strings.clone` | `string` | `delete(s)` |
| `strings.clone_to_cstring` | `cstring` | `delete(cs)` |
| `strings.join` | `string` | `delete(s)` |
| `strings.concatenate` | `string` | `delete(s)` |
| `strings.repeat` | `string` | `delete(s)` |
| `strings.replace` | `string` | `delete(s)` |
| `strings.replace_all` | `string` | `delete(s)` |
| `strings.to_upper` | `string` | `delete(s)` |
| `strings.to_lower` | `string` | `delete(s)` |
| `strings.trim_*` (allocating variants) | `string` | `delete(s)` |
| `strings.split` | `[]string` | `delete(parts)` |
| `strings.split_n` | `[]string` | `delete(parts)` |
| `strings.split_after` | `[]string` | `delete(parts)` |
| `strings.fields` | `[]string` | `delete(parts)` |
| `strings.builder_make` | `strings.Builder` | `strings.builder_destroy(&b)` |

### `core:fmt`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `fmt.aprintf` | `string` | `delete(s)` |
| `fmt.aprintfln` | `string` | `delete(s)` |
| `fmt.aprint` | `string` | `delete(s)` |
| `fmt.aprintln` | `string` | `delete(s)` |

Note: `fmt.tprintf` / `fmt.tprint` allocate on `context.temp_allocator` — they
do NOT need `delete` but MUST NOT be stored past the temp scope (C028).

### `core:os`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `os.read_entire_file` | `[]u8, bool` | `delete(data)` |
| `os.read_entire_file_from_path` | `[]u8, Error` | `delete(data)` |
| `os.read_entire_file_from_filename` | `[]u8, Error` | `delete(data)` |

### `core:path/filepath`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `filepath.abs` | `string, bool` | `delete(s)` |

### `core:encoding/json`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `json.marshal` | `[]u8, Error` | `delete(data)` |
| `json.marshal_string` | `string, Error` | `delete(s)` |

### `core:mem`
| Procedure | Returns | Free with |
|-----------|---------|-----------|
| `mem.alloc` | `rawptr, Error` | `free(ptr)` |
| `mem.alloc_bytes` | `[]u8, Error` | `free(raw_data(b))` |
| `mem.clone` | `^T` | `free(ptr)` |
| `mem.clone_slice` | `[]T` | `delete(s)` |

### SCM pattern for known stdlib allocators

```scheme
; Extension of memory_safety.scm — known allocating stdlib calls
(short_var_decl
  (identifier_list (identifier) @var)
  (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier) @pkg
        field:   (field_identifier) @fn)
      (#match? @pkg "^(strings|fmt|os|mem|filepath|json)$")
      (#match? @fn "^(clone|clone_to_cstring|join|concatenate|repeat|replace|replace_all|to_upper|to_lower|split|split_n|split_after|fields|builder_make|aprintf|aprintfln|aprint|aprintln|read_entire_file|read_entire_file_from_path|read_entire_file_from_filename|abs|marshal|marshal_string|alloc|alloc_bytes|clone_slice)$")))) @stdlib_alloc
```

Same C001 escape hatches apply: suppress if `defer delete(@var)` exists in
block, or if `@var` is returned.

---

## Appendix B — Fixture Templates for Highest-Priority Rules

Ready-to-use test fixture structures. Each has a pass and a fail variant.

### C032 — defer in for loop

```odin
// tests/C032/c032_pass_explicit_free.odin
package test_c032_pass

test_explicit_free :: proc() {
    items := []string{"a", "b", "c"}
    for item in items {
        buf := make([]u8, 128)
        _ = item
        delete(buf)              // explicit delete at end of loop — correct
    }
}

test_defer_outside_loop :: proc() {
    buf := make([]u8, 1024)
    defer delete(buf)           // defer outside loop — correct
    for i in 0..<10 {
        buf[i] = u8(i)
    }
}
```

```odin
// tests/C032/c032_fail_defer_in_loop.odin
package test_c032_fail

test_defer_in_loop :: proc() {
    for i in 0..<1000 {
        buf := make([]u8, 1024)
        defer delete(buf)        // C032: defer in loop — buf leaks until proc exits
        _ = buf[0]
    }
}

test_defer_in_for_range :: proc() {
    items := []string{"a", "b", "c"}
    for item in items {
        scratch := make(map[string]int)
        defer delete(scratch)    // C032: defer in loop
        _ = item
    }
}
```

Expected output for fail fixture:
```
c032_fail_defer_in_loop.odin:6:9: C032 [correctness] `defer` inside `for` loop runs
when the procedure exits, not each iteration. Use explicit `delete(buf)` at end of
loop body instead.

c032_fail_defer_in_loop.odin:14:9: C032 [correctness] `defer` inside `for` loop runs
when the procedure exits, not each iteration. Use explicit `delete(scratch)` at end of
loop body instead.
```

---

### C029 — strings.split not freed

```odin
// tests/C029/c029_pass_deferred.odin
package test_c029_pass

import "core:strings"

test_split_freed :: proc() {
    parts := strings.split("a,b,c", ",")
    defer delete(parts)          // correct
    for p in parts { _ = p }
}

test_split_returned :: proc() -> []string {
    return strings.split("a,b,c", ",")  // ownership transferred — no warn
}
```

```odin
// tests/C029/c029_fail_not_freed.odin
package test_c029_fail

import "core:strings"

test_split_leak :: proc() {
    parts := strings.split("a,b,c", ",")  // C029: no defer delete(parts)
    for p in parts { _ = p }
}

test_clone_leak :: proc() {
    s := strings.clone("hello")           // C029: no defer delete(s)
    _ = s
}
```

---

### C028 — tprintf stored past temp scope

```odin
// tests/C028/c028_pass_immediate_use.odin
package test_c028_pass

import "core:fmt"

// tprintf used immediately — not stored — correct
test_immediate :: proc() {
    fmt.println(fmt.tprintf("value: %d", 42))
}

// aprintf used for storage — correct
test_aprintf :: proc() {
    s := fmt.aprintf("value: %d", 42)
    defer delete(s)
    store_string(s)
}
```

```odin
// tests/C028/c028_fail_stored.odin
package test_c028_fail

import "core:fmt"

MyStruct :: struct { label: string }

// C028: tprintf result stored in struct field
test_store_in_struct :: proc() -> MyStruct {
    s := fmt.tprintf("item_%d", 42)
    return MyStruct{ label = s }   // s is temp-allocated — dangling after return
}

// C028: tprintf result returned
test_return_tprintf :: proc() -> string {
    return fmt.tprintf("value: %d", 42)  // caller receives temp memory
}
```

---

## Appendix C — odin-lint.toml Config Schema Additions

New config keys introduced by this addendum:

```toml
# Post-V7 rules — all OFF by default

[rules.C021]
enabled = false   # Go-style fmt calls — turn on for mixed Go/Odin teams

[rules.C029]
# stdlib allocator tracking — extends C001 with known stdlib alloc procs
enabled = true
# Which stdlib packages to track (default: all known)
packages = ["strings", "fmt", "os", "mem"]

[rules.C032]
enabled = true    # defer in for loop — high value, should be ON by default

[rules.C028]
enabled = true    # tprintf stored past temp scope — CONTEXTUAL

[rules.C033]
enabled = true    # strings.Builder not destroyed

[rules.C036]
enabled = false   # magic allocation sizes — opt-in
min_size = 256    # only flag literals >= this value

[rules.C037]
enabled = false   # trailing return in void proc — opt-in

[rules.P001]
enabled = false   # inconsistent error convention — library mode
# minimum proc count before firing (avoids noise in small packages)
min_procs = 3

[rules.P002]
enabled = false   # undocumented exported procs — library mode

# Domain shorthand — enables sensible rule groups
[domains]
# existing domains from V7.6:
# ffi, odin_2026, semantic_naming
# new:
stdlib_safety = true   # enables C029, C028, C033 as a group
go_migration  = false  # enables C021-C027 — for teams migrating from Go
library_mode  = false  # enables P001, P002
```

The `stdlib_safety` domain is the most important new addition — it bundles
C028, C029, and C033 into a single opt-in that catches the most common
stdlib memory mistakes without requiring per-rule configuration.

---

## Appendix D — LLM Guide Chapter Cross-Reference

Full mapping of which LLM guide chapter each rule addresses:

| Chapter | Topic | Rules |
|---------|-------|-------|
| Ch 1 | Package system | — (no new rules needed — compiler catches) |
| Ch 2 | Basic types | — |
| Ch 3 | Procedures | C030 (or_return), C037 (trailing return) |
| Ch 4 | Control flow | C022 (range loop), C032 (defer in loop) |
| Ch 5 | Structs | — |
| Ch 6 | Memory model | C028 (tprintf scope), C029 (stdlib allocs) |
| Ch 7 | Pointers | C023 (C deref syntax) |
| Ch 8 | Strings | C021 (fmt calls), C029, C033 (builder) |
| Ch 9 | Arrays/slices | C025 (append without &), C036 (magic size) |
| Ch 10 | Maps | C029 (map alloc tracking) |
| Ch 11 | Unions | — |
| Ch 12 | Interfaces/vtables | — |
| Ch 13 | Concurrency | C026 (go keyword), C027 (channels) |
| Ch 14 | Dynamic arrays | C025 (append), C034 (unused index blank) |
| Ch 15 | Top LLM mistakes | C021, C022, C023, C025, C032 |
| Ch 16 | Error handling | C024 (errors pkg), C030 (or_return), C031 (panic) |

Notable gap: Chapters 1, 2, 5, 11, 12 have no new rules because the
mistakes there are either caught by the compiler or require type information
(M6 scope). Chapter 13 (concurrency) rules C026/C027 are low-priority because
they are compile errors and the correct approach (core:thread, core:sync) is
well-documented.

---

*Document complete*
*Status: PROPOSED — implement after V7 stabilisation (Gate 3 complete)*
*Highest priority: C032, C029, C028, C021, C022, C023, C025*
*Previous discussion: plans/odin-lint-implementation-planV7.md*
*Source: LLM Guide odin_llm_guide_complete2.md + V7.6 Analysis Scope Model*
