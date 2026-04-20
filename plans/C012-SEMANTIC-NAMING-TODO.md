# C012: Semantic Ownership Naming — Implementation TODO
*Rule tier: INFO / CONTEXTUAL (opt-in, never VIOLATION)*
*Milestone: M3.3 (syntactic checks) ✅ COMPLETE · M6 (type-gated checks) ⬜ PLANNED*
*Config: disabled by default — enabled via `--enable-c012` flag (M3.3) or `odin-lint.toml` (M4+)*

---

## What C012 Is

A set of **naming convention suggestions** that encode memory ownership
semantics directly in variable names. The goal is twofold:

1. **Human readability** — a developer can scan a function and immediately
   know which variables own heap memory without reading every allocation site.

2. **LLM reasoning** — the DNA exporter can tag `memory_role` automatically
   from variable name suffixes, giving the AI model ownership context without
   type inference. A model fine-tuned on `_owned`-annotated code learns Odin
   ownership patterns faster and makes fewer memory mistakes.

C012 never fires VIOLATION. It fires INFO when a variable *could* carry
a semantic suffix but doesn't. The developer chooses whether to adopt it.

---

## The Four Conventions

### Convention 1: `_owned` suffix — heap-allocated, caller must free

**When to suggest:**
- A `short_var_decl` or `assignment_statement` assigns the result of
  `make()` or `new()` to a variable without `_owned` in its name
- A procedure *returns* a slice, dynamic array, map, or pointer that
  was allocated inside it, and the return variable has no `_owned` suffix

**Examples:**

```odin
// INFO fired — suggest _owned suffix
results := make([]string, 0, 16)
data    := new(MyStruct)

// No INFO — already correct
results_owned := make([]string, 0, 16)
data_owned    := new(MyStruct)

// No INFO — returned from function, suppressed by escape hatch
get_items :: proc() -> []string {
    items := make([]string, 10)  // no INFO: items is returned (ownership transfer)
    return items
}
// But the *caller* should name it:
my_items_owned := get_items()  // INFO if not _owned
```

**Message:**
`"Variable holds allocated memory but name does not signal ownership.
Consider suffix '_owned' to clarify that caller must free this value."`

**Fix hint:**
`"Rename to '<name>_owned' and ensure a matching 'defer delete(<name>_owned)'
exists in this scope."`

**SCM query (syntactic, M3.3):**
```scheme
; Capture make/new assignments without _owned in the variable name
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @fn
      (#match? @fn "^(make|new)$")))
  (#not-match? @var_name "_owned$")) @alloc_without_owned
```

**DNA exporter benefit:**
If `_owned` is present, `dna_exporter.odin` can automatically set
`"memory_role": "allocator"` for procedures that return `_owned` variables,
and `"returns_owned": true` on the return field — with zero type inference.

---

### Convention 2: `_borrowed` or `_view` suffix — points into memory owned elsewhere

**When to suggest:**
- A slice is created from an existing slice or dynamic array via slicing syntax
  (`buf[a:b]`, `arr[:]`) and the result has no `_view` or `_borrowed` in its name
- A pointer parameter is received and stored locally without indicating it's borrowed

**Examples:**

```odin
// INFO fired — slice of owned data, no ownership signal
header := buf[0:4]
chunk  := data[offset:]

// No INFO — name signals it's a view
header_view    := buf[0:4]
chunk_borrowed := data[offset:]
```

**Message:**
`"Variable is a view into existing memory but name does not signal borrowing.
Consider suffix '_view' or '_borrowed' to clarify this must not be freed."`

**Fix hint:**
`"Rename to '<name>_view'. Never call delete() on a borrowed slice."`

**SCM query (syntactic, M3.3):**
```scheme
; Capture slice expressions assigned without _view or _borrowed
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (slice_expression) @slice)
  (#not-match? @var_name "(_view|_borrowed)$")) @slice_without_view
```

---

### Convention 3: `allocator` in name — variables of type `mem.Allocator`

**When to suggest:**
- A variable holds a `mem.Allocator` or `mem.Allocator_Proc` value and
  the name gives no hint that it's an allocator (e.g. named `ctx`, `a`, `x`)

**Examples:**

```odin
// INFO fired — allocator with opaque name
a   := context.allocator
ctx := mem.tracking_allocator(&track)

// No INFO — name is clear
my_allocator    := context.allocator
tracking_alloc  := mem.tracking_allocator(&track)
arena_allocator := virtual.arena_allocator(&arena)
```

**Message:**
`"Variable holds an allocator but name does not signal its role.
Consider including 'allocator' or 'alloc' in the name."`

**Fix hint:**
`"Rename to include 'allocator' or 'alloc' (e.g. 'arena_allocator').
This makes allocator flow visible to readers and analysis tools."`

**Implementation note:**
This check requires knowing the variable's type is `mem.Allocator`. It
cannot be reliably detected from the AST alone — the type is only visible
via OLS type resolution. Defer this sub-rule to **M6**.

For M3.3, a weaker heuristic: if the RHS of an assignment contains a call
to `mem.tracking_allocator`, `virtual.arena_allocator`, or
`context.temp_allocator`, and the LHS name doesn't contain `alloc`, suggest.

```scheme
; Heuristic (M3.3): known allocator-returning calls with opaque LHS name
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (selector_expression
        field: (field_identifier) @fn
        (#match? @fn "^(tracking_allocator|arena_allocator|temp_allocator)$"))))
  (#not-match? @var_name "(alloc|allocator)")) @alloc_var_without_name
```

**DNA exporter benefit:**
Procedures with `allocator` in parameter names or local variable names are
automatically tagged `"accepts_allocator": true` in `symbols.json`, making
allocator-threading patterns visible in the call graph.

---

### Convention 4: `_arena` suffix — variables of type `mem.Arena` or `virtual.Arena`

**When to suggest:**
- A variable holds an arena struct value and the name doesn't include `arena`

**Examples:**

```odin
// INFO fired — arena with no name signal
scratch: mem.Arena
block:   virtual.Arena

// No INFO
scratch_arena: mem.Arena
temp_arena:    virtual.Arena
```

**Message:**
`"Variable holds an arena allocator but name does not signal its role.
Consider suffix '_arena' for clarity."`

**Implementation note:** Same type-gating issue as Convention 3.
Heuristic for M3.3: check the declared type identifier directly —
if node_type is a type declaration containing `Arena` in the type name,
check the variable name.

```scheme
; M3.3 heuristic: declared type contains "Arena" but name doesn't
(var_declaration
  name: (identifier) @var_name
  type: (type_identifier) @type_name
  (#match? @type_name "Arena")
  (#not-match? @var_name "arena")) @arena_without_suffix
```

---

## Implementation Phases

### Phase 1 — M3.3: Syntactic Rules ✅ COMPLETE

These fire based on AST patterns alone using the SCM query engine.
Implementation lives in `src/core/c012_rules.scm` + `c012_scm_run`.

| Sub-rule | Convention | SCM file | Status | Notes |
|----------|-----------|----------|--------|-------|
| C012-S1 | `_owned` on make/new assignments | `c012_rules.scm` | ✅ | INFO tier |
| C012-S2 | `_view`/`_borrowed` on slice expressions | `c012_rules.scm` | ✅ | INFO tier |
| C012-S3 | `alloc` heuristic on known allocator calls | `c012_rules.scm` | ✅ | INFO tier |
| C012-S4 | `_arena` on Arena type declarations | `c012_rules.scm` | ⬜ | Deferred to M6: type annotation matching needed |

Key finding during M3.3: `:=` inside procedure bodies is `assignment_statement`
in the Odin tree-sitter grammar, NOT `variable_declaration` (which is package scope
only). All S-rules updated accordingly.

### Phase 2 — M6: Type-Gated Rules (OLS type info required)

| Sub-rule | Convention | Requires | Status |
|----------|-----------|----------|--------|
| C012-S4 | `_arena` on `mem.Arena`/`virtual.Arena` declarations | OLS type OR type-name heuristic | ⬜ |
| C012-T1 | `alloc` in name for any `mem.Allocator`-typed variable | OLS type resolution | ⬜ |
| C012-T2 | `_arena` in name for any `mem.Arena`-typed variable | OLS type resolution | ⬜ |
| C012-T3 | `_owned` on return values from allocator-role procedures | OLS + DNA export | ⬜ |

---

## Configuration (odin-lint.toml)

C012 is **off by default**. Enable it explicitly:

```toml
[rules.C012]
enabled = true

# Which sub-conventions to enforce (default: all when enabled)
owned_suffix   = true   # _owned on allocations
view_suffix    = true   # _view/_borrowed on slices
allocator_name = true   # 'alloc' in allocator variable names
arena_suffix   = true   # _arena on arena variables

# Severity (default: info — never VIOLATION)
severity = "info"   # or "contextual"
```

---

## Gate Criteria

### M3.3 Gate ✅ PASSED

- [x] C012-S1 fires on `buf := make([]u8, n)` when C012 enabled
- [x] C012-S1 is silent on `buf_owned := make([]u8, n)`
- [x] C012-S1 is silent when make result is immediately returned
- [x] C012-S2 fires on `header := buf[0:4]` when C012 enabled
- [x] C012-S2 is silent on `header_view := buf[0:4]`
- [x] C012-S3 fires on `x := mem.tracking_allocator(&t)` when C012 enabled
- [x] C012-S3 is silent on `my_alloc := mem.tracking_allocator(&t)`
- [x] All C012 rules completely silent when disabled (default)
- [x] C012 diagnostics use DiagnosticType.INFO — never VIOLATION
- [x] 3 pass + 3 fail fixtures for S1, S2, S3
- [x] `--list-rules` marks C012 as "(opt-in)"
- [ ] C012-S4 (arena type declarations) — deferred to M6
- [ ] `odin-lint.toml` per-sub-rule config — deferred to M4 (config loading)
- [ ] `--explain C012` output — deferred to M4.1

### M6 Gate (C012 Type-Gated Phase)

*Prerequisite: Gate 5 (OLS plugin + type resolution working)*

- [ ] C012-T1 fires on `mem.Allocator`-typed variable with no `alloc`/`allocator` in name
- [ ] C012-T1 is silent on variables already named `*_allocator`, `*_alloc`, etc.
- [ ] C012-T2 fires on `mem.Arena` or `virtual.Arena`-typed variable without `arena` in name
- [ ] C012-T2 is silent on `scratch_arena`, `temp_arena`, `block_arena`
- [ ] C012-T3 fires when callee's DNA `memory_role == "allocator"` and LHS has no `_owned`
- [ ] C012-T3 requires `--enable-c012` and is silent otherwise (default off)
- [ ] C012-S4 (arena declarations) promoted from heuristic to type-exact
- [ ] `dna_exporter.odin` `infer_memory_role_from_name` uses all suffix/name signals
- [ ] `symbols.json` `memory_role` field populated for 100% of procedures
- [ ] 3 pass + 3 fail fixtures for each T sub-rule
- [ ] False positive rate on RuiShin < 5% for all T sub-rules

---

## Integration with DNA Exporter

When C012 conventions are adopted, `dna_exporter.odin` can derive
memory roles **without type inference**, purely from name patterns:

```odin
// In dna_exporter.odin — infer memory role from name suffixes
infer_memory_role_from_name :: proc(name: string) -> string {
    if strings.has_suffix(name, "_owned")    do return "allocator"
    if strings.has_suffix(name, "_borrowed") do return "borrower"
    if strings.has_suffix(name, "_view")     do return "borrower"
    if strings.contains(name,   "allocator") do return "allocator_ref"
    if strings.has_suffix(name, "_arena")    do return "arena"
    return "neutral"
}
```

This produces richer `symbols.json` entries automatically:

```json
{
  "name": "load_config",
  "returns": [
    {
      "name": "config_owned",
      "inferred_role": "allocator",
      "note": "caller must free"
    }
  ]
}
```

The Gemma 4 fine-tuning pipeline uses this signal directly:
- Training examples with `_owned` suffix teach the model that this
  variable requires a `defer delete` in the calling scope
- Training examples with `_view` suffix teach the model never to free
  the variable — even if it's a `[]u8` that "looks" like owned memory

This is the key payoff: **the naming convention bridges the gap between
the static linter and the AI layer with zero additional tooling**.

---

## Escape Hatches (No INFO fired)

C012 must be silent in all of these cases:

| Situation | Reason |
|-----------|--------|
| Variable is immediately returned | Ownership transfers to caller |
| Variable is assigned `nil` or zero value | Not an allocation |
| Variable name already contains the keyword | Convention is met |
| File is in excluded path (core/, vendor/) | Different conventions |
| C012 is disabled in odin-lint.toml | Default off |
| Variable is a proc parameter | Convention applies to declaration, not use |
| The `// odin-lint:ignore C012` comment is present | Explicit suppression |

---

## Relationship to Other Rules

| Rule | Relationship |
|------|-------------|
| C001 | C012-S1 and C001 target the same allocation pattern. C001 fires VIOLATION for missing `defer free`; C012 fires INFO for missing `_owned` name. They are complementary — C001 catches the runtime bug, C012 nudges towards a codebase where the bug is less likely to be missed. |
| C002 | C012 naming makes double-free detection easier: two `defer free` calls on the same `_owned` variable is unambiguous. |
| C011 | C012 conventions extend naturally to FFI: a C string that's been `strings.clone()`d should be named `str_owned`; a raw C pointer view should be `str_view`. |
| C003-C008 | C012 is a separate opt-in layer on top of the mandatory naming rules. C003-C008 are always-on style rules; C012 is semantic and opt-in. |

---

## Files to Create

```
src/core/c012-SEM-Naming.odin           # Rule implementation
tests/C012_SEM_NAMING/
    c012_fixture_pass_owned.odin        # _owned present — no INFO
    c012_fixture_pass_view.odin         # _view present — no INFO
    c012_fixture_pass_disabled.odin     # C012 off — no INFO
    c012_fixture_fail_owned.odin        # make without _owned — INFO
    c012_fixture_fail_view.odin         # slice without _view — INFO
    c012_fixture_fail_allocator.odin    # allocator call with opaque name
    TEST_SUMMARY.md
ffi/tree_sitter/queries/naming_rules.scm  # add C012 patterns here
```

---

## M6 Implementation Detail

*This section is the agent prompt / task spec for implementing C012 Phase 2.*
*Prerequisite: M5 complete (OLS plugin returning type information).*

### What OLS provides that M3.3 could not use

OLS resolves every identifier to its declared type. After M5, the odin-lint
OLS plugin path (`src/rules/correctness/`) receives `^ast.File` with full
type information. The C012 M6 rules live on this OLS path — they do NOT use
tree-sitter SCM queries, because the SCM path has no type info.

```
C012 Phase 2 implementation path:
  src/rules/correctness/c012-OLS-Naming.odin   ← NEW file for M6
  Uses: ^ast.File, ast.Visitor, type_checker results
  NOT: tree-sitter, SCM queries
```

### C012-T1: `mem.Allocator` typed variables

**Detection logic:**
1. Walk all `var_decl` and `short_var_decl` nodes via `ast.Visitor`
2. For each, ask OLS type checker: is the resolved type `mem.Allocator`
   or `mem.Allocator_Proc`?
3. If yes and variable name does not contain `alloc` or `allocator` → INFO

**Implementation sketch:**
```odin
c012_t1_check :: proc(
    node:      ^ast.Expr,
    type_info: ^types.Type,
    var_name:  string,
    file_path: string,
) -> Maybe(Diagnostic) {
    // Only fire if type is mem.Allocator
    if !type_is_allocator(type_info) do return nil

    // Name already signals allocator — silent
    if strings.contains(var_name, "alloc") do return nil
    if strings.contains(var_name, "allocator") do return nil

    return Diagnostic{
        file      = file_path,
        line      = node.pos.line,
        rule_id   = "C012",
        tier      = "style",
        message   = "Variable holds a mem.Allocator but name gives no signal. Consider including 'alloc' or 'allocator'.",
        fix       = fmt.aprintf("Rename to '%v_allocator' or '%v_alloc'", var_name, var_name),
        diag_type = .INFO,
    }
}
```

**`type_is_allocator` helper:**
```odin
type_is_allocator :: proc(t: ^types.Type) -> bool {
    // Check for mem.Allocator (named type)
    if named, ok := t.(^types.Named); ok {
        return named.obj.pkg.path == "core:mem" &&
               (named.obj.name == "Allocator" || named.obj.name == "Allocator_Proc")
    }
    return false
}
```

---

### C012-T2: `mem.Arena` / `virtual.Arena` typed variables

Same pattern as T1, checking for arena types:

```odin
type_is_arena :: proc(t: ^types.Type) -> bool {
    if named, ok := t.(^types.Named); ok {
        arena_pkgs := []string{"core:mem", "core:mem/virtual"}
        for pkg in arena_pkgs {
            if named.obj.pkg.path == pkg && named.obj.name == "Arena" {
                return true
            }
        }
    }
    return false
}
```

Name check: variable must contain `arena`. `scratch`, `block`, `temp` alone
are not sufficient — they must be `scratch_arena`, `block_arena`, `temp_arena`.

---

### C012-T3: `_owned` on allocator-procedure return values

This is the most complex sub-rule. It fires when:
1. A procedure call's return value is assigned without `_owned` suffix, AND
2. The callee is known to be an "allocator" — meaning it returns heap-allocated
   memory that the caller must free

**How "allocator callee" is determined (two sources, in priority order):**

Source A — DNA export (M5.6): if `symbols.json` / SQLite has the callee's
`memory_role == "allocator"`, that is authoritative.

Source B — C012 naming convention in the callee's own body: if the callee
procedure has a `_owned` suffix on its return variable, it signals ownership
transfer. This is detectable without the DNA export.

```odin
// Callee has _owned return — C012-T3 can infer this proc is an allocator
load_config :: proc() -> Config {
    cfg_owned := Config{ ... }   // _owned signals: caller takes ownership
    return cfg_owned
}

// Caller should name the result _owned
cfg := load_config()        // C012-T3 INFO
cfg_owned := load_config()  // silent
```

**Implementation note:** T3 requires a two-pass approach or pre-built callee
index. Build the index during the OLS plugin's document-open phase:
scan all proc declarations in the workspace for `_owned` return variables;
store in a `map[string]bool` (proc name → is_allocator). Then T3 check is
a map lookup per call site.

**Escape hatches for T3:**
- Callee is in `core/`, `vendor/` — skip (different conventions)
- Return value is immediately passed to another call (no local name) — skip
- C012 is disabled — skip
- `// odin-lint:ignore C012` present — skip

---

### DNA Exporter Integration (M5.6 dependency)

The `infer_memory_role_from_name` function in `dna_exporter.odin` must be
updated to use all C012 signals:

```odin
infer_memory_role_from_name :: proc(
    proc_name:    string,
    return_names: []string,   // names of return variables
    param_names:  []string,   // names of parameters
) -> string {
    // Check return variables for _owned suffix
    for name in return_names {
        if strings.has_suffix(name, "_owned") do return "allocator"
    }
    // Check if any parameter is an allocator
    for name in param_names {
        if strings.contains(name, "alloc") || strings.contains(name, "allocator") {
            return "borrower"  // takes allocator = borrows memory management
        }
    }
    return "neutral"
}
```

This ensures `symbols.json` `memory_role` is populated for every procedure
as soon as C012 conventions are adopted — feeding C012-T3 and the AI pipeline
simultaneously.

---

### Files to Create for M6

```
src/rules/correctness/c012-OLS-Naming.odin   # T1, T2, T3 implementation
tests/C012_SEM_NAMING/
    c012_t1_fixture_pass.odin    # mem.Allocator var with 'alloc' in name
    c012_t1_fixture_fail.odin    # mem.Allocator var with opaque name
    c012_t2_fixture_pass.odin    # mem.Arena var with 'arena' in name
    c012_t2_fixture_fail.odin    # mem.Arena var without 'arena'
    c012_t3_fixture_pass.odin    # _owned on allocator proc return
    c012_t3_fixture_fail.odin    # no _owned on allocator proc return
    M6_TEST_SUMMARY.md
```

---

*Updated: April 2026 — M3.3 complete, M6 specification added*
*Milestone: M3.3 ✅ COMPLETE · M6 ⬜ PLANNED (after Gate 5)*
*Rule tier: INFO — opt-in via `--enable-c012` or `odin-lint.toml`*
