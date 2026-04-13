# odintooling — Migration Plan to V7
*From the Current Working Codebase to the Full V7 Architecture*
*Revision 1.0 · April 2026 — Step-by-Step with Exact Instructions*

---

## How to Read This Document

This plan is written to be **completely unambiguous**. Every step says:
- **WHAT** exactly to do (file name, function name, code snippet)
- **WHY** it is needed (the reason this exists)
- **HOW** to verify it worked (test command + expected output)

Each Milestone has a **Gate** at the end. You must pass every Gate check before
moving to the next Milestone. If a check fails, fix it before continuing — do not
accumulate technical debt across milestones.

**Time investment:** This plan has 9 milestones. Each can be worked on independently.
Milestones 0–2 are already complete.

---

## Table of Contents

1. [Current State Snapshot](#1-current-state-snapshot)
2. [What V7 Adds (Summary)](#2-what-v7-adds-summary)
3. [Pre-Migration Cleanup (Required Before Starting)](#3-pre-migration-cleanup)
4. [Migration Track A — Query Engine (M3.1)](#4-migration-track-a--query-engine-m31)
5. [Migration Track B — C002 SCM Rewrite (M3.2)](#5-migration-track-b--c002-scm-rewrite-m32)
6. [Migration Track C — C003–C008 Real Implementation (M3.3)](#6-migration-track-c--c003c008-real-implementation-m33)
7. [Migration Track D — Odin 2026 Rules (M3.4)](#7-migration-track-d--odin-2026-rules-m34)
8. [Milestone 4 — CLI Enhancements](#8-milestone-4--cli-enhancements)
9. [Milestone 4.5 — Autofix Layer](#9-milestone-45--autofix-layer)
10. [Milestone 5 — OLS Plugin (Real Implementation)](#10-milestone-5--ols-plugin-real-implementation)
11. [Milestone 5.5 — MCP Gateway](#11-milestone-55--mcp-gateway)
12. [Milestone 5.6 — DNA Impact Analysis](#12-milestone-56--dna-impact-analysis)
13. [Migration Progress Checklist](#13-migration-progress-checklist)

---

## 1. Current State Snapshot

This is exactly what exists right now in `src/core/`. Every file, its status, and
what role it plays. **Do not assume — check.**

### Files That Exist and Work (Keep As-Is)

| File | Lines | Status | Purpose |
|------|-------|--------|---------|
| `main.odin` | 295 | ✅ Functional | CLI entry point, sequential rule runner |
| `c001-COR-Memory.odin` | 553 | ✅ Production-ready | Memory allocation without free |
| `c002-COR-Pointer.odin` | 416 | ✅ Production-ready | Double-free detection |
| `tree_sitter.odin` | 240 | ✅ Complete | High-level tree-sitter adapter |
| `tree_sitter_bindings.odin` | 71 | ✅ Complete (partial) | FFI bindings — node/tree API only |
| `suppression.odin` | 200 | ✅ Complete | Inline `// odin-lint:ignore` parsing |
| `ast.odin` | 127 | ✅ Complete | `ASTNode` struct and walk helpers |

### Files That Exist But Are Stubs (Need Real Implementation)

| File | Lines | Status | Problem |
|------|-------|--------|---------|
| `c003-STY-Naming.odin` | 70 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `c004-STY-Private.odin` | 59 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `c005-STY-Internal.odin` | 59 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `c006-STY-Public.odin` | 59 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `c007-STY-Types.odin` | 62 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `c008-STY-Acronyms.odin` | 65 | ⚠️ Stub | Returns empty diagnostics — no real check |
| `plugin_main.odin` | 78 | ⚠️ Stub | Exported proc returns nil |
| `odin_lint_plugin.odin` | 39 | ⚠️ Stub | Duplicate of plugin_main, returns test diag |

### Files That Do NOT Exist (Must Be Created)

| File | Milestone | Purpose |
|------|-----------|---------|
| `query_engine.odin` | M3.1 | S-expression query runner |
| `ffi/tree_sitter/queries/*.scm` | M3.1–M3.4 | SCM pattern files |
| `autofix.odin` | M4.5 | `FixEdit` generation and application |
| `dna_exporter.odin` | M5.6 | `symbols.json` exporter |
| `src/mcp/mcp_server.odin` | M5.5 | MCP HTTP server |
| `src/mcp/mcp_tools.odin` | M5.5 | MCP tool implementations |
| `src/mcp/server_card.json` | M5.5 | MCP capability discovery |

### Files That Must Be Deleted (Clutter / Confusion Risk)

| File | Why Delete |
|------|-----------|
| `c002-COR-Pointer.odin.backup` | 24,099 lines of old code; confuses editors and AI |
| `c002-COR-Pointer.odin.improved.re` | 15,616 lines; same reason |
| `c002-COR-Pointer.odin.old` | 15,368 lines; same reason |
| `main.odin.backup` | Stale backup; git history is the backup |
| `main.odin.backup2` | Same |

### What the Current CLI Can Do

```
./artifacts/odin-lint <file.odin>
```

- Parses the file with tree-sitter
- Runs C001 (memory leak detection) ✅
- Runs C002 (double-free detection) ✅
- Runs a simple `TODO/FIXME` text scan (stub)
- Prints violations with emoji and exits 1 if any found

**What it cannot do yet:**
- `--help`, `--list-rules`, `--rule C001`, `--format json` (no CLI flags)
- Apply fixes automatically
- Run SCM/S-expression queries (no query API bindings)
- Export structured symbol data
- Communicate via MCP

---

## 2. What V7 Adds (Summary)

Before touching any code, understand what is being built and why.

### The Big Picture

```
TODAY (V6 state):                    V7 TARGET:

odin-lint <file>                     odin-lint <file> [flags]
    │                                    │
    ├── C001 (manual AST walk)           ├── C001 (SCM query)
    ├── C002 (manual AST walk)           ├── C002 (SCM query)
    └── TODO scan (text grep)            ├── C003–C008 (SCM query, real)
                                         ├── C009 (os/old migration)
                                         └── C010 (Small_Array migration)
                                                  │
                                         odin-lint --export-symbols
                                              → symbols.json
                                              → callers, callees, memory roles
                                                  │
                                         MCP Server (port 6789)
                                              → get_dna_context()
                                              → run_lint_denoise()
                                              → ols_apply_edit()
```

### Why Each Piece Matters

**SCM Query Engine (M3.1):** The current C001/C002 rules use ~80 lines of nested
loop traversal to find a pattern that a 5-line S-expression query can express.
The query engine makes rules faster to write, easier to read, and shareable with
Neovim/Helix (they use the same query format).

**C003–C008 Real Implementation (M3.3):** These rules are registered and named but
currently do nothing. Every Odin developer is silently missing naming violation
warnings.

**Odin 2026 Rules (M3.4):** Two time-sensitive rules: the deprecated `core:os/old`
package will be removed in Q3 2026, and `Small_Array` has a superior replacement.
These rules protect codebases from future breakage.

**DNA Exporter (M5.6):** The linter already knows which procedures allocate memory,
which free it, and which have violations. Exporting this as `symbols.json` turns
the linter into a semantic knowledge base that AI models can query — instead of
reading source text blindly, an AI agent can ask "show me all allocators" and get
a structured answer.

**MCP Gateway (M5.5):** Makes all of the above accessible to AI coding assistants
(Claude Code, Cursor, Copilot) via the Model Context Protocol standard.

---

## 3. Pre-Migration Cleanup

**Do this first. Do not skip. Estimated time: 15 minutes.**

### Step 3.1 — Delete Obsolete Files

These files are not used by the build and will confuse any tool (including AI
agents) that reads the codebase.

```bash
cd /Users/rainer/SynologyDrive/Development/MyODIN/odintooling

# Verify they are not imported anywhere before deleting
grep -r "c002-COR-Pointer.odin.backup" src/
grep -r "main.odin.backup" src/

# If grep returns nothing, safe to delete:
rm src/core/c002-COR-Pointer.odin.backup
rm src/core/c002-COR-Pointer.odin.improved.re
rm src/core/c002-COR-Pointer.odin.old
rm src/core/main.odin.backup
rm src/core/main.odin.backup2
```

**Why:** The `.backup` files are 55,000+ lines of dead code. Every AI tool that
reads `src/core/` will try to parse them. They increase context costs, slow
exploration, and introduce confusion about which version is current.

### Step 3.2 — Resolve Duplicate Plugin Files

There are two plugin files doing the same thing differently:
- `src/core/plugin_main.odin` (78 lines) — exports `get_odin_lint_plugin()`
- `src/core/odin_lint_plugin.odin` (39 lines) — also exports `get_odin_lint_plugin()`

This will cause a linker error when both are in the same package. Decide which to
keep:

- **Keep:** `src/core/plugin_main.odin` (more complete structure)
- **Delete:** `src/core/odin_lint_plugin.odin`

```bash
rm src/core/odin_lint_plugin.odin
```

Then confirm the build still works:

```bash
./scripts/build.sh
# Expected: artifacts/odin-lint compiled without errors
./artifacts/odin-lint tests/C001_COR_MEMORY/c001_fixture_fail.odin
# Expected: at least one 🔴 violation printed
```

### Step 3.3 — Create the queries/ Directory

The SCM query files need a home. Create it now so all future milestones can
reference it.

```bash
mkdir -p ffi/tree_sitter/queries
```

**Why:** All `.scm` pattern files for all rules will live here. Keeping them
outside `src/` means they are not compiled — they are loaded at runtime.

### Step 3.4 — Commit the Cleanup

```bash
git add -A
git commit -m "Cleanup: remove 55k lines of obsolete backup files, resolve duplicate plugin"
```

### Gate 3 — Pre-Migration Cleanup

| Check | Command | Expected |
|-------|---------|----------|
| No backup files | `ls src/core/*.backup 2>/dev/null` | No output |
| No duplicate plugin | `grep -l "get_odin_lint_plugin" src/core/` | One file only |
| Build succeeds | `./scripts/build.sh` | Exit 0, binary created |
| C001 still works | `./artifacts/odin-lint tests/C001_COR_MEMORY/c001_fixture_fail.odin` | Violations printed |
| C002 still works | `./artifacts/odin-lint tests/C002_COR_POINTER/c002_fixture_fail.odin` | Violations printed |
| queries dir exists | `ls ffi/tree_sitter/queries/` | Empty directory |

**Do not proceed to M3.1 until all 6 checks pass.**

---

## 4. Migration Track A — Query Engine (M3.1)

**Prerequisite:** Gate 3 passed.
**Estimated complexity:** Medium — 3 new files, ~150 lines total.
**Risk:** Low — purely additive, does not modify any existing file.

### What Is Being Built

Tree-sitter has a built-in S-expression query language. Right now the codebase
has no bindings to the query API. This milestone adds:

1. **FFI bindings** for the 7 tree-sitter query functions (added to `tree_sitter_bindings.odin`)
2. **Two new structs** — `TSQueryMatch` and `TSQueryCapture` — for receiving query results
3. **A new file** `query_engine.odin` — the high-level Odin interface to compile and run queries
4. **The first SCM file** `ffi/tree_sitter/queries/memory_safety.scm`

### Why SCM Instead of Manual Walking

The current C001 manual walker works like this (simplified):

```
for each node in the AST:
    if node.type == "short_var_decl":
        for each child of node:
            if child.type == "expression_list":
                for each grandchild of child:
                    if grandchild.type == "call_expression":
                        ... (40 more lines)
```

The SCM equivalent:
```scheme
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @fn
      (#match? @fn "^(make|new)$")))) @alloc
```

Same detection, 6 lines instead of 60. The query engine compiles this pattern
once at startup and runs it at C speed for every file.

### Step 4.1 — Add Query API Bindings

Open `src/core/tree_sitter_bindings.odin`. Find the end of the existing `foreign ts`
block (around line 65). Add the following **after** the existing bindings, inside
the same `foreign ts` block:

```odin
    // --- Query API (M3.1) ---
    ts_query_new :: proc(
        language:     rawptr,
        source:       cstring,
        source_len:   u32,
        error_offset: ^u32,
        error_type:   ^TSQueryError,
    ) -> rawptr ---
    ts_query_delete             :: proc(query: rawptr) ---
    ts_query_capture_count      :: proc(query: rawptr) -> u32 ---
    ts_query_capture_name_for_id :: proc(
        query:   rawptr,
        id:      u32,
        length:  ^u32,
    ) -> cstring ---
    ts_query_cursor_new         :: proc() -> rawptr ---
    ts_query_cursor_delete      :: proc(cursor: rawptr) ---
    ts_query_cursor_exec        :: proc(cursor: rawptr, query: rawptr, node: TSNode) ---
    ts_query_cursor_next_match  :: proc(cursor: rawptr, match: ^TSQueryMatch) -> bool ---
```

Also add the new structs and enum to `tree_sitter_bindings.odin` **outside** the
`foreign` block, near the other struct definitions:

```odin
TSQueryError :: enum u32 {
    None      = 0,
    Syntax    = 1,
    NodeType  = 2,
    Field     = 3,
    Capture   = 4,
    Structure = 5,
    Language  = 6,
}

TSQueryCapture :: struct {
    node:  TSNode,
    index: u32,
}

TSQueryMatch :: struct {
    id:            u32,
    pattern_index: u16,
    capture_count: u16,
    captures:      ^TSQueryCapture,
}
```

**Why these specific functions:**
- `ts_query_new` — compiles a `.scm` string into a compiled query object (do once)
- `ts_query_cursor_new/exec/next_match` — the iteration API (run per file)
- `ts_query_capture_name_for_id` — lets us look up capture names by index (`@var_name` → "var_name")

### Step 4.2 — Create query_engine.odin

Create the file `src/core/query_engine.odin`. This is the high-level Odin wrapper
that rules will use. They never call raw FFI directly.

```odin
package core

import "core:fmt"
import "core:os"
import "core:strings"

// QueryResult holds one match from a compiled SCM query.
// captures maps capture name (e.g. "var_name") to the matched TSNode.
QueryResult :: struct {
    captures:      map[string]TSNode,
    pattern_index: int,
}

// CompiledQuery wraps a compiled tree-sitter query and its capture name table.
// Create once at startup with load_query(); pass to run_query() per file.
CompiledQuery :: struct {
    handle:        rawptr,          // ts_query handle
    capture_names: []string,        // index → capture name string
    language:      rawptr,
}

// load_query compiles an SCM file into a CompiledQuery.
// scm_path: path to a .scm file (e.g. "ffi/tree_sitter/queries/memory_safety.scm")
// language: the TSLanguage pointer (from initTreeSitter)
// Returns: (query, true) on success, ({}, false) on error.
load_query :: proc(language: rawptr, scm_path: string) -> (CompiledQuery, bool) {
    data, ok := os.read_entire_file(scm_path)
    if !ok {
        fmt.eprintln("[query_engine] Failed to read SCM file:", scm_path)
        return {}, false
    }
    defer delete(data)

    source     := strings.clone_to_cstring(string(data))
    defer delete(source)

    error_offset: u32
    error_type:   TSQueryError
    handle := ts_query_new(language, source, u32(len(data)), &error_offset, &error_type)

    if handle == nil || error_type != .None {
        fmt.eprintfln("[query_engine] SCM compile error in %s at byte %d: %v",
            scm_path, error_offset, error_type)
        return {}, false
    }

    // Build capture name table (index → string)
    count  := ts_query_capture_count(handle)
    names  := make([]string, count)
    for i in 0..<count {
        length: u32
        raw := ts_query_capture_name_for_id(handle, i, &length)
        names[i] = strings.clone(string(raw[:length]))
    }

    return CompiledQuery{
        handle        = handle,
        capture_names = names,
        language      = language,
    }, true
}

// unload_query frees a CompiledQuery's resources.
// Call this at shutdown (once per query, not per file).
unload_query :: proc(q: ^CompiledQuery) {
    if q.handle != nil {
        ts_query_delete(q.handle)
        q.handle = nil
    }
    for name in q.capture_names {
        delete(name)
    }
    delete(q.capture_names)
}

// run_query runs a compiled query over an AST root node.
// Returns a slice of QueryResult — one entry per match found.
// Caller must delete the returned slice and each result's captures map.
run_query :: proc(
    q:          ^CompiledQuery,
    root:       TSNode,
    file_lines: []string,
) -> []QueryResult {
    results := make([dynamic]QueryResult)

    cursor := ts_query_cursor_new()
    defer ts_query_cursor_delete(cursor)

    ts_query_cursor_exec(cursor, q.handle, root)

    match: TSQueryMatch
    for ts_query_cursor_next_match(cursor, &match) {
        result := QueryResult{
            captures      = make(map[string]TSNode),
            pattern_index = int(match.pattern_index),
        }
        for i in 0..<int(match.capture_count) {
            cap := match.captures[i]
            if int(cap.index) < len(q.capture_names) {
                name := q.capture_names[cap.index]
                result.captures[name] = cap.node
            }
        }
        append(&results, result)
    }

    return results[:]
}

// free_query_results frees the slice returned by run_query.
free_query_results :: proc(results: []QueryResult) {
    for &r in results {
        delete(r.captures)
    }
    delete(results)
}
```

### Step 4.3 — Write the First SCM File

Create `ffi/tree_sitter/queries/memory_safety.scm`:

```scheme
; memory_safety.scm
; Captures for C001 (memory allocation without defer free)
; and C002 (double-free via defer).
;
; C001: Capture every make() or new() call assigned to a local variable.
;   @var_name = the LHS identifier (the variable being allocated into)
;   @alloc    = the entire short_var_decl node
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @alloc_fn
      (#match? @alloc_fn "^(make|new)$")))) @alloc

; C002: Capture every defer free() or defer delete() call.
;   @freed_var   = the identifier being freed
;   @cleanup_fn  = "free" or "delete"
(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var))) @defer_free
```

**How to verify this file is syntactically valid:** The tree-sitter CLI has a
query validation mode. If you have it installed:
```bash
tree-sitter query ffi/tree_sitter/queries/memory_safety.scm tests/C001_COR_MEMORY/c001_fixture_fail.odin
```
If not installed, the `load_query` function will print a compile error with the
exact byte offset if the SCM syntax is wrong.

### Step 4.4 — Add a Query Engine Smoke Test

Add a test script `scripts/test_query_engine.sh`:

```bash
#!/bin/bash
# Smoke test: confirm query engine compiles and runs without crash.
echo "=== Query Engine Smoke Test ==="
./artifacts/odin-lint --test-query ffi/tree_sitter/queries/memory_safety.scm \
    tests/C001_COR_MEMORY/c001_fixture_fail.odin

if [ $? -eq 0 ]; then
    echo "✅ Query engine: OK"
else
    echo "❌ Query engine: FAILED"
    exit 1
fi
```

> Note: the `--test-query` flag does not exist yet — it will be added as part of
> M4 CLI enhancements. For now, the smoke test is manual: add a temporary
> `fmt.println` to `main.odin` that loads the query and prints the match count,
> then remove it after confirming it works.

### Gate M3.1 — Query Engine

| Check | How to Verify | Expected |
|-------|--------------|---------|
| FFI bindings compile | `./scripts/build.sh` | No errors |
| `load_query` succeeds | Temporary print in main.odin | "Query loaded: 2 captures" |
| `run_query` returns matches | Temporary print in main.odin | N > 0 matches on fail fixture |
| C001 output unchanged | `./scripts/run_c001_tests.sh` | Same pass/fail as before |
| C002 output unchanged | `./scripts/run_c002_tests.sh` | Same pass/fail as before |

**What "unchanged" means:** The query engine runs in parallel with the existing
manual walkers. Both must produce the same violations. If they differ, the
query version has a bug.

---

## 5. Migration Track B — C002 SCM Rewrite (M3.2)

**Prerequisite:** Gate M3.1 passed.
**Why this is done before C003–C008:** C002 is complex. Migrating it validates
that the query engine can handle real complexity before applying it to new rules.

### What Changes

The current C002 uses a manual recursive AST walk with a scope stack to detect
when the same variable is freed twice via `defer`. The SCM version:

1. Uses the `defer_free` pattern from `memory_safety.scm` to find all defers
2. Groups them by variable name
3. Reports any variable that appears in more than one `defer free()`

The manual walker is **not deleted yet** — it runs in parallel (Shadow mode)
until both produce identical output on the test corpus.

### Step 5.1 — Add c002_scm_matcher to c002-COR-Pointer.odin

At the bottom of `src/core/c002-COR-Pointer.odin`, add a new proc that uses the
query engine:

```odin
// c002_scm_matcher is the SCM-based replacement for c002Matcher.
// It is run in Shadow mode (parallel to the manual walker) until
// verified correct, then replaces it.
//
// How it works:
//   1. Run the defer_free query to find all "defer free(var)" occurrences
//   2. Group by freed variable name
//   3. Any variable freed more than once in the same procedure is a violation
c002_scm_matcher :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    // Count: var_name → list of (line, col) where it appears in a defer free
    free_sites := make(map[string][dynamic]Position)
    defer {
        for _, &sites in free_sites { delete(sites) }
        delete(free_sites)
    }

    for result in results {
        freed_node, has_freed := result.captures["freed_var"]
        if !has_freed { continue }

        name := extract_node_text(freed_node, file_lines)
        if name == "" || name == "_" { continue }

        pt   := ts_node_start_point(freed_node)
        pos  := Position{line = int(pt.row) + 1, col = int(pt.column) + 1}
        append(&free_sites[name], pos)
    }

    diagnostics := make([dynamic]Diagnostic)

    for var_name, sites in free_sites {
        if len(sites) < 2 { continue }

        // First site: the first defer free — that is fine
        // Second+ sites: violations
        for i in 1..<len(sites) {
            site := sites[i]
            append(&diagnostics, Diagnostic{
                file      = file_path,
                line      = site.line,
                col       = site.col,
                rule_id   = "C002",
                tier      = "CORRECTNESS",
                message   = fmt.aprintf(
                    "Double-free: '%s' is already freed by a defer in this scope",
                    var_name,
                ),
                diag_type = .VIOLATION,
            })
        }
    }

    return diagnostics[:]
}
```

### Step 5.2 — Enable Shadow Mode in main.odin

In `src/core/main.odin`, after the existing C002 run (around line 270), add:

```odin
// SHADOW MODE: Run SCM C002 in parallel and compare outputs.
// Remove this block once parity is confirmed.
when ODIN_DEBUG {
    scm_diags := c002_scm_matcher(file_path, root_node, file_lines, &memory_query)
    defer delete(scm_diags)

    if len(scm_diags) != len(c002_diagnostics) {
        fmt.eprintfln(
            "[shadow] C002 parity FAIL: manual=%d SCM=%d for %s",
            len(c002_diagnostics), len(scm_diags), file_path,
        )
    }
}
```

**Why `when ODIN_DEBUG`:** The shadow comparison is only compiled in debug builds.
It does not affect production performance. Build with `odin build src/core -debug`
to enable it.

### Step 5.3 — Run Parity Test on Full Corpus

```bash
# Build in debug mode for shadow comparison
odin build src/core -out:artifacts/odin-lint-debug -debug \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a"

# Run against C002 test fixtures
./scripts/run_c002_tests.sh 2>&1 | grep "\[shadow\]"
# Expected: no "[shadow] C002 parity FAIL" lines

# Run against RuiShin real-world codebase (if available)
./scripts/test_ruishin.sh 2>&1 | grep "\[shadow\]"
# Expected: no failures
```

Log all divergences to `tests/c002_query_parity_report.txt`.

### Step 5.4 — Retire the Manual Walker

**Only do this after parity is confirmed on the full test corpus.**

In `main.odin`:
1. Remove the manual `c002Matcher` call
2. Replace with `c002_scm_matcher`
3. Remove the shadow comparison block

In `c002-COR-Pointer.odin`:
1. Keep `c002_scm_matcher` as the primary function
2. Mark `c002Matcher` as `@(deprecated)` and leave it for one release cycle
3. Remove `c002Matcher` in the next milestone

### Gate M3.2 — C002 via SCM

| Check | Command | Expected |
|-------|---------|---------|
| Zero parity failures | Debug build + corpus run | No `[shadow] FAIL` output |
| C002 fixture fail | `./scripts/run_c002_tests.sh` | All 22 fixtures: same results |
| C002 false positive rate | Manual inspection of RuiShin results | < 5% |
| Build succeeds | `./scripts/build.sh` (release) | Exit 0 |

---

## 6. Migration Track C — C003–C008 Real Implementation (M3.3)

**Prerequisite:** Gate M3.1 passed. (M3.2 runs in parallel — not required.)

### Why These Rules Are Currently Useless

Look at any of the stub rule files, e.g. `src/core/c003-STY-Naming.odin`:

```odin
c003Matcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic {
    return nil  // ← returns nothing, always
}
```

Every Odin developer using the linter gets zero naming feedback. These rules
need real implementations.

### Step 6.1 — Create naming_rules.scm

Create `ffi/tree_sitter/queries/naming_rules.scm`:

```scheme
; naming_rules.scm
; Captures for C003 (proc names), C004 (private visibility),
; C006 (public doc comments), C007 (type names), C008 (acronyms).

; C003 / C004 / C006 / C008: Capture every procedure declaration.
;   @proc_name = the procedure name identifier
(procedure_declaration
  name: (identifier) @proc_name)

; C007: Capture every type declaration.
;   @type_name = the type name identifier
(type_declaration
  name: (identifier) @type_name)

; C006: Capture proc declarations with a preceding comment.
;   Used to check whether public procs have doc comments.
(comment) @doc_comment
```

### Step 6.2 — Implement C003 (snake_case proc names)

Replace the stub in `src/core/c003-STY-Naming.odin`:

```odin
package core

import "core:fmt"
import "core:strings"
import "core:unicode"

c003Matcher :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        proc_node, has := result.captures["proc_name"]
        if !has { continue }

        name := extract_node_text(proc_node, file_lines)
        if name == "" || strings.has_prefix(name, "_") { continue }

        // Skip: main, init, test_ prefix (special Odin names)
        if name == "main" || name == "init" { continue }
        if strings.has_prefix(name, "test_") { continue }

        if !is_snake_case(name) {
            pt := ts_node_start_point(proc_node)
            append(&diagnostics, Diagnostic{
                file      = file_path,
                line      = int(pt.row) + 1,
                col       = int(pt.column) + 1,
                rule_id   = "C003",
                tier      = "STYLE",
                message   = fmt.aprintf(
                    "Procedure '%s' should be snake_case", name),
                fix       = fmt.aprintf(
                    "Rename to: %s", to_snake_case(name)),
                has_fix   = true,
                diag_type = .VIOLATION,
            })
        }
    }
    return diagnostics[:]
}

// is_snake_case returns true if the name is all lowercase letters,
// digits, and underscores, and does not start with a digit.
is_snake_case :: proc(name: string) -> bool {
    if len(name) == 0 { return false }
    for r, i in name {
        if i == 0 && unicode.is_digit(r) { return false }
        if !unicode.is_lower(r) && !unicode.is_digit(r) && r != '_' {
            return false
        }
    }
    return true
}
```

Apply the same pattern for C007 (`type_name` capture → must be `PascalCase`),
C004 (private procs), C005 (internal procs), C006 (doc comments), and C008
(acronym handling). Each rule is ~30–50 lines following the same structure:
query result → check the captured name → emit diagnostic if wrong.

### Step 6.3 — Wire Rules Into main.odin

In `main.odin`, the naming query is loaded once and passed to all C003–C008 matchers:

```odin
// Load naming query once at startup
naming_query, naming_ok := load_query(ts_language, "ffi/tree_sitter/queries/naming_rules.scm")
if !naming_ok {
    fmt.eprintln("Failed to load naming rules query")
    os.exit(1)
}
defer unload_query(&naming_query)

// Run all naming rules on the same query results
c003_diags := c003Matcher(file_path, root_node, file_lines, &naming_query)
c007_diags := c007Matcher(file_path, root_node, file_lines, &naming_query)
// ... etc
```

**Why one query for all naming rules:** All naming rules capture from the same
AST node types. Running the query once and dispatching to multiple rule checkers
is more efficient than running 6 separate queries.

### Gate M3.3 — Naming Rules C003–C008

| Check | How | Expected |
|-------|-----|---------|
| C003 fires on camelCase proc | Write test fixture with `fooBar :: proc()` | 🔴 violation |
| C003 silent on snake_case | Write test fixture with `foo_bar :: proc()` | No output |
| C007 fires on lowercase type | Write test fixture with `myType :: struct {}` | 🔴 violation |
| C007 silent on PascalCase | Write test fixture with `MyType :: struct {}` | No output |
| No regression on C001/C002 | `./scripts/run_c001_tests.sh && ./scripts/run_c002_tests.sh` | All pass |
| 3 pass + 3 fail fixtures per rule | `ls tests/C003_STY_NAMING/` etc. | 6+ files each |

---

## 7. Migration Track D — Odin 2026 Rules (M3.4)

**Prerequisite:** Gate M3.1 passed.
**Time sensitivity:** `core:os/old` is removed from Odin in Q3 2026. These rules
are highest-priority for Odin developers who want to stay current.

### Context You Must Understand Before Writing These Rules

**C009 — core:os/old deprecation:**

In Q1 2026, the Odin core team completed the `core:os2` migration. The result:
- `core:os` = the NEW, correct API (same as what was `core:os2`)
- `core:os/old` = the DEPRECATED legacy API (removed Q3 2026)

**This is the critical fact:** if you write a rule that flags `import "core:os"`,
you will flag CORRECT code. That is wrong. The rule must flag `import "core:os/old"`.

**C010 — Small_Array superseded:**

`core:container/small_array.Small_Array(N, T)` was the way to create a
stack-backed fixed-capacity array. As of Odin dev-2026-04, the language has a
built-in syntax: `x: [dynamic; 8]int`. The old way still compiles but is now
idiomatic debt.

### Step 7.1 — Create odin2026_migration.scm

Create `ffi/tree_sitter/queries/odin2026_migration.scm`:

```scheme
; odin2026_migration.scm
; Detects usage of deprecated Odin APIs that will break in Q3 2026.

; C009: Detect import of deprecated core:os/old package.
; The new correct package is simply "core:os".
; DO NOT flag "core:os" — that is correct code.
(import_declaration
  path: (interpreted_string_literal) @import_path
  (#match? @import_path "\"core:os/old\"")) @legacy_os_import

; C010: Detect usage of Small_Array from core:container/small_array.
; Superseded by the built-in [dynamic; N]T syntax in dev-2026-04.
(call_expression
  function: (selector_expression
    field: (field_identifier) @fn_name
    (#eq? @fn_name "Small_Array"))) @small_array_call
```

### Step 7.2 — Implement C009

Create `src/core/c009-MIG-LegacyOS.odin`:

```odin
package core

import "core:fmt"

// C009 flags import of "core:os/old" — the deprecated legacy OS package.
//
// WHY THIS EXISTS:
//   The Odin core:os2 migration completed in Q1 2026. The new API is now
//   simply "core:os". The old API moved to "core:os/old" and will be
//   REMOVED IN Q3 2026. Any codebase still using core:os/old will fail
//   to compile after that removal.
//
// WHAT TO DO:
//   1. Change: import os "core:os/old"  →  import os "core:os"
//   2. Update call sites: the new API requires explicit allocator params
//      on procedures that return allocated memory. Check the Odin changelog
//      at odin-lang.org for the full migration guide.
//
// FALSE POSITIVE RISK: Zero. This only fires on the exact string "core:os/old".
//   It will NEVER fire on "core:os" (the correct new import).

C009Rule :: proc() -> Rule {
    return Rule{
        id      = "C009",
        tier    = "MIGRATION",
        message = "Import of deprecated 'core:os/old' — this package is removed in Q3 2026",
        fix     = "Replace with 'core:os'. See: odin-lang.org/news/moving-towards-a-new-core-os/",
    }
}

c009Matcher :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    results := run_query(q, root_node, file_lines)
    defer free_query_results(results)

    diagnostics := make([dynamic]Diagnostic)

    for result in results {
        import_node, has := result.captures["legacy_os_import"]
        if !has { continue }

        pt := ts_node_start_point(import_node)
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = int(pt.row) + 1,
            col       = int(pt.column) + 1,
            rule_id   = "C009",
            tier      = "MIGRATION",
            message   = `Import of deprecated "core:os/old" — removed Q3 2026`,
            fix       = `Replace with "core:os"`,
            has_fix   = false,  // Autofix requires updating call sites too
            diag_type = .VIOLATION,
        })
    }

    return diagnostics[:]
}
```

### Step 7.3 — Implement C010

Create `src/core/c010-MIG-SmallArray.odin` following the same structure:

```odin
package core

import "core:fmt"

// C010 flags usage of Small_Array(N, T) from core:container/small_array.
//
// WHY THIS EXISTS:
//   Odin dev-2026-04 introduced built-in fixed-capacity dynamic arrays with
//   the syntax: x: [dynamic; 8]int
//   This is idiomatic, stack-backed, and works with all standard dynamic array
//   procedures. Small_Array is now redundant idiom debt.
//
// WHAT TO DO:
//   Small_Array(8, int) → [dynamic; 8]int

C010Rule :: proc() -> Rule { ... }

c010Matcher :: proc(
    file_path:  string,
    root_node:  TSNode,
    file_lines: []string,
    q:          ^CompiledQuery,
) -> []Diagnostic {
    // Same pattern as c009Matcher — uses "small_array_call" capture
    ...
}
```

### Gate M3.4 — Odin 2026 Migration Rules

| Check | Test File | Expected |
|-------|-----------|---------|
| C009 fires on `core:os/old` | `import os "core:os/old"` | 🔴 MIGRATION violation |
| C009 silent on `core:os` | `import os "core:os"` | No output — this is correct! |
| C009 silent on `core:os2` | `import os "core:os2"` | No output (os2 path doesn't exist post-Q1 2026 but don't flag it) |
| C010 fires on Small_Array | `x := small_array.Small_Array(8, int){}` | 🔴 MIGRATION violation |
| C010 silent on `[dynamic; N]T` | `x: [dynamic; 8]int` | No output |
| Self-test: our codebase | `./scripts/test_our_codebase.sh` | 0 violations (we don't use os/old) |

---

## 8. Milestone 4 — CLI Enhancements

**Prerequisite:** Gate 3 (cleanup). M3.x milestones can be in progress.
**Why this matters:** Currently the tool has zero flags. `--format json` is
needed for CI pipelines. `--rule` filtering is needed for adoption (let teams
turn on one rule at a time). `--list-rules` is needed for discoverability.

### Step 8.1 — Parse odin-lint.toml

The config file exists but is never read. Add a `Config` struct and parser in
a new file `src/core/config.odin`:

```odin
package core

import "core:fmt"
import "core:os"
import "vendor:toml"  // or parse manually if no toml package available

Config :: struct {
    rules:       map[string]RuleConfig,
    ignore_paths: []string,
    report_format: string,  // "text", "json", "sarif"
    fail_on_warnings: bool,
}

RuleConfig :: struct {
    level:    string,  // "error", "warn", "disabled"
    category: string,
}

load_config :: proc(path: string) -> (Config, bool) { ... }
```

### Step 8.2 — Add CLI Flag Parsing to main.odin

Replace the current arg parsing (lines 176–183 in main.odin) with:

```odin
CLIArgs :: struct {
    file:         string,
    rules:        []string,   // --rule C001,C002
    format:       string,     // --format text|json|sarif
    list_rules:   bool,       // --list-rules
    export_sym:   bool,       // --export-symbols
    fix:          bool,       // --fix
    fix_dry_run:  bool,       // --fix-dry-run
}

parse_args :: proc() -> (CLIArgs, bool) {
    args := os.args[1:]
    if len(args) == 0 {
        print_usage()
        return {}, false
    }
    // Parse flags...
}

print_usage :: proc() {
    fmt.println(`Usage: odin-lint <file.odin> [flags]

Flags:
  --rule C001,C002     Run only the specified rules (comma-separated)
  --format text|json   Output format (default: text)
  --list-rules         List all available rules and exit
  --export-symbols     Export symbols.json instead of running lint
  --fix                Apply safe automatic fixes
  --fix-dry-run        Show what --fix would do without applying

Examples:
  odin-lint main.odin
  odin-lint main.odin --rule C001 --format json
  odin-lint main.odin --export-symbols > symbols.json`)
}
```

### Step 8.3 — JSON Output Format

When `--format json` is passed, emit diagnostics as JSON instead of text:

```json
{
  "schema": "odin-lint-diagnostics/1.0",
  "file": "src/core/main.odin",
  "violations": [
    {
      "rule_id": "C001",
      "tier": "CORRECTNESS",
      "line": 42,
      "col": 5,
      "message": "Allocated 'file_lines' via make() without matching defer free()",
      "fix": "Add: defer delete(file_lines)",
      "has_fix": true
    }
  ],
  "summary": {
    "total": 1,
    "errors": 1,
    "warnings": 0
  }
}
```

### Gate 4 — CLI Enhancements

| Check | Command | Expected |
|-------|---------|---------|
| --help works | `./artifacts/odin-lint --help` | Usage text printed, exit 0 |
| --list-rules works | `./artifacts/odin-lint --list-rules` | Table of all rules |
| --rule filter works | `./artifacts/odin-lint test.odin --rule C001` | Only C001 results |
| JSON format valid | `./artifacts/odin-lint test.odin --format json \| jq .` | No jq errors |
| Config parsed | Add `C001 = { level = "disabled" }` to toml, run lint | C001 silent |
| All prior tests pass | `./scripts/comprehensive_odin_test.sh` | No regressions |

---

## 9. Milestone 4.5 — Autofix Layer

**Prerequisite:** Gate 4 passed. SCM captures from M3.1 must be working.

### What Is a FixEdit

A `FixEdit` is the smallest unit of code change: "replace text at this location
with this new text." This is how every autofix works — LSP code actions,
`rustfmt`, `gofmt`, and now odin-lint.

```odin
// src/core/autofix.odin (new file)
package core

Position :: struct { line, col: int }

FixEdit :: struct {
    file:     string,
    start:    Position,
    end:      Position,
    new_text: string,
}

// apply_fix applies a single FixEdit to a file's content.
// Returns the new file content as a string.
apply_fix :: proc(content: string, edit: FixEdit) -> string { ... }

// apply_fixes applies multiple non-overlapping edits in reverse order
// (high line numbers first) so earlier edits don't invalidate later positions.
apply_fixes :: proc(content: string, edits: []FixEdit) -> string { ... }
```

### Step 9.1 — C001 Autofix

The C001 fix is: "after the allocation line, insert `\tdefer free(var_name)\n`."

The SCM `@var_name` capture from `memory_safety.scm` gives us the exact variable
name and the position of the allocation. The fix is:

```odin
fix_for_c001 :: proc(result: QueryResult) -> FixEdit {
    alloc_node  := result.captures["alloc"]   // the whole short_var_decl
    var_node    := result.captures["var_name"] // the LHS identifier

    end_pt  := ts_node_end_point(alloc_node)
    var_txt := // extract text from var_node

    return FixEdit{
        start    = {line = int(end_pt.row) + 1, col = 0},
        end      = {line = int(end_pt.row) + 1, col = 0},
        new_text = fmt.aprintf("\tdefer free(%s)\n", var_txt),
    }
}
```

**Why SCM captures make this reliable:** The SCM query returns the exact AST node
for the allocation and the variable name. There is no text scanning, no regex,
no approximation. The fix insert position is the line immediately after the
allocation node ends — exactly where `defer free` belongs.

### Gate 4.5 — Autofix

| Check | Command | Expected |
|-------|---------|---------|
| --fix-dry-run shows edits | `./artifacts/odin-lint c001_fail.odin --fix-dry-run` | Shows proposed insert |
| --fix applies edit | `cp c001_fail.odin /tmp/test.odin && ./artifacts/odin-lint /tmp/test.odin --fix` | File modified |
| Re-lint after fix | `./artifacts/odin-lint /tmp/test.odin` | 0 violations |
| --fix is idempotent | Run --fix twice | Second run: "0 fixes applied" |

---

## 10. Milestone 5 — OLS Plugin (Real Implementation)

**Prerequisite:** Gate 4 passed.

### Current State

`src/core/plugin_main.odin` exports `get_odin_lint_plugin()` which returns a
`PluginHandle` where all callbacks are stubs. The `odin_lint_analyze_file` proc
returns `nil` always.

### What Needs to Change

The OLS plugin path uses `^ast.File` from `core:odin/ast` — this is the Odin
compiler's own AST, richer than tree-sitter's view. The plugin rules live in
`src/rules/correctness/` (separate from `src/core/`) and receive this AST.

### Step 10.1 — Implement odin_lint_analyze_file

In `plugin_main.odin`, replace the stub with real rule dispatch:

```odin
odin_lint_analyze_file :: proc "c" (document_uri: ^byte, ast_file: rawptr) -> rawptr {
    context = runtime.default_context()

    // Cast the ast_file to ^odin_ast.File
    file := cast(^odin_ast.File)ast_file

    diagnostics := make([dynamic]SimpleDiagnostic)

    // Run each rule that has an OLS path implementation
    c001_results := c001_ols_matcher(file)
    for d in c001_results {
        append(&diagnostics, diagnostic_to_simple(d))
    }

    // ... c002_ols_matcher, c003_ols_matcher, etc.

    // Convert to C-compatible return value
    return diagnostics_to_c_array(diagnostics[:])
}
```

### Gate 5 — OLS Plugin

| Check | How | Expected |
|-------|-----|---------|
| Plugin builds without errors | `./scripts/build_plugin.sh` | `.dylib` created |
| OLS loads plugin | Check OLS log after restart | "odin-lint plugin loaded" |
| C001 diagnostic appears | Open a file with an allocation without free | Red squiggle in editor |
| Quick fix offered | Hover over C001 squiggle | "Add defer free()" code action |

---

## 11. Milestone 5.5 — MCP Gateway

**Prerequisite:** Gate 5 passed.

### What Is MCP

Model Context Protocol (MCP) is the standard (as of April 2026, under Linux
Foundation governance) for AI assistants to call external tools. An MCP server
exposes tools that an AI (Claude, Cursor, Copilot, etc.) can call by name with
JSON arguments.

By building an MCP server around odin-lint, any AI assistant that supports MCP
can call `run_lint_denoise(code)` and get back structured violation data, or call
`get_dna_context(proc_name)` and get back the procedure's call graph.

### Step 11.1 — Create src/mcp/ Package

```bash
mkdir -p src/mcp
```

Create `src/mcp/mcp_server.odin` — an HTTP server on `localhost:6789` that
speaks the MCP JSON-RPC 2.0 protocol with Streamable HTTP transport:

```odin
package mcp

import "core:net"
import "core:fmt"
import "core:encoding/json"

MCP_PORT :: 6789

// start_server starts the MCP server. Blocks until shutdown.
start_server :: proc() {
    listener, err := net.listen_tcp({port = MCP_PORT})
    // ... accept loop, parse JSON-RPC, dispatch to tools
}
```

### Step 11.2 — Implement MCP Tools in mcp_tools.odin

```odin
package mcp

// The 8 tools exposed to AI agents:

// 1. get_dna_context — subgraph of a procedure (M5.6 fills this fully)
// 2. get_impact_radius — what changes if this proc changes
// 3. find_allocators — all allocator-role procedures
// 4. run_lint_denoise — run linter on a code snippet, return JSON errors
// 5. ols_get_symbol — symbol info from OLS
// 6. ols_apply_edit — apply a text edit via OLS
// 7. ols_get_diagnostics — all lint diagnostics for a file
// 8. ols_export_symbols — generate symbols.json for a file
```

### Step 11.3 — Create server_card.json

Create `src/mcp/server_card.json`. This is the MCP standard "capability
discovery" file — AI tools look here to understand what this server does:

```json
{
  "schema": "mcp-server-card/1.0",
  "name": "odin-lint",
  "version": "7.1.0",
  "description": "Semantic linting and code intelligence for the Odin programming language",
  "tools": [
    {
      "name": "run_lint_denoise",
      "description": "Run odin-lint on a code snippet and return structured violations for AI to fix",
      "parameters": {
        "code": "string — Odin source code to lint",
        "rules": "string (optional) — comma-separated rule IDs to check"
      }
    },
    {
      "name": "get_dna_context",
      "description": "Get semantic context for a procedure: callers, callees, memory role",
      "parameters": {
        "proc_name": "string — procedure name to look up"
      }
    }
  ],
  "transport": "streamable-http",
  "endpoint": "http://localhost:6789/mcp"
}
```

**Why Streamable HTTP, not stdio:**
- stdio only works when the MCP server is a child process of the client
- Streamable HTTP works across processes, survives restarts, supports multiple clients
- Required for IDE integration (VS Code, Cursor, Zed) which run in separate processes

### Gate 5.5 — MCP Gateway

| Check | Command | Expected |
|-------|---------|---------|
| Server starts | `./artifacts/odin-lint --mcp-server` | "MCP server listening on :6789" |
| Server card accessible | `curl http://localhost:6789/.well-known/mcp` | JSON server card |
| run_lint_denoise works | `curl -X POST ... --data '{"code":"x := make([]u8, 10)"}` | C001 violation in JSON |
| ols_export_symbols works | MCP call with file path | Valid symbols.json |
| Integrate with Claude Code | Add to `~/.claude/mcp_servers.json` | Tools appear in Claude |

---

## 12. Milestone 5.6 — DNA Impact Analysis

**Prerequisite:** Gate 5.5 passed.
**This milestone delivers the AI advantage** — the hybrid graph-RAG index that
lets a local Gemma 4 model understand your Odin codebase better than a frontier
model reading raw source.

### What Gets Built

A new file `src/core/dna_exporter.odin` that, when invoked with `--export-symbols`,
produces a `symbols.json` file containing:

1. **Structural graph:** every procedure with its callers, callees, and call depth
2. **Memory ownership role:** is this proc an allocator, deallocator, borrower, or neutral?
3. **Lint quality signal:** does this proc have violations? (AI uses only clean code)
4. **Optional vector embedding:** `--embed` flag generates text embedding per symbol

### Step 12.1 — Create dna_exporter.odin

```odin
// src/core/dna_exporter.odin
package core

import "core:fmt"
import "core:encoding/json"

SymbolExport :: struct {
    name:           string,
    file:           string,
    line:           int,
    signature:      string,
    memory_role:    string,   // "allocator" | "deallocator" | "borrower" | "neutral"
    allocates:      []string,
    frees:          []string,
    callers:        []string,
    callees:        []string,
    call_depth:     int,
    lint_violations: []string,
}

DNAExport :: struct {
    schema:     string,
    generated:  string,
    file:       string,
    procedures: []SymbolExport,
}

// export_symbols analyzes a file and writes symbols.json.
// Called when odin-lint is invoked with --export-symbols.
export_symbols :: proc(file_path: string, output_path: string) -> bool { ... }
```

### Step 12.2 — Memory Role Classification

This is the most important part. Add a `classify_memory_role` proc that looks at
what the C001 analysis already knows:

```odin
// classify_memory_role determines the memory ownership role of a procedure.
// An ALLOCATOR creates and returns owned memory.
// A DEALLOCATOR frees memory passed to it.
// A BORROWER uses memory without owning it.
// NEUTRAL has no memory involvement.
classify_memory_role :: proc(
    proc_name:    string,
    allocates:    []string,  // from C001 analysis
    frees:        []string,  // from C001 analysis
    returns_ptrs: bool,      // does the proc return a pointer type?
) -> string {
    if len(allocates) > 0 && returns_ptrs { return "allocator" }
    if len(frees) > 0 && len(allocates) == 0 { return "deallocator" }
    if len(allocates) > 0 && !returns_ptrs { return "borrower" }
    return "neutral"
}
```

### Step 12.3 — New MCP Tools from M5.6

Update `mcp_tools.odin` with the tools that use the DNA data:

```
get_dna_context(proc_name)
  → { callers, callees, memory_role, allocates, frees, lint_violations }

get_impact_radius(proc_name)
  → { all procedures transitively affected by changing this proc }

find_allocators()
  → { all procedures with memory_role = "allocator" }

run_lint_denoise(code: string)
  → { violations: [{rule_id, line, col, message, fix}] }
```

### Gate 5.6 — DNA Impact Analysis

| Check | Command | Expected |
|-------|---------|---------|
| symbols.json generated | `./artifacts/odin-lint src/core/main.odin --export-symbols` | Valid JSON file |
| callers populated | Check symbols.json for a known proc | `callers` field non-empty |
| memory_role correct | Check `c001Matcher` in symbols.json | `"memory_role": "borrower"` |
| MCP get_dna_context | MCP call for `c001Matcher` | Returns callers + callees |
| run_lint_denoise | MCP call with violation code | Returns C001 violation JSON |
| Hybrid index ready | `--embed` flag | `symbols.vec` file created |

---

## 13. Migration Progress Checklist

Print this and check off each item as you complete it.

### Pre-Migration Cleanup
- [ ] Deleted: `c002-COR-Pointer.odin.backup` (24k lines)
- [ ] Deleted: `c002-COR-Pointer.odin.improved.re` (15k lines)
- [ ] Deleted: `c002-COR-Pointer.odin.old` (15k lines)
- [ ] Deleted: `main.odin.backup`, `main.odin.backup2`
- [ ] Deleted: `odin_lint_plugin.odin` (duplicate)
- [ ] Created: `ffi/tree_sitter/queries/` directory
- [ ] Build verified after cleanup

### M3.1 — Query Engine
- [ ] Added query API bindings to `tree_sitter_bindings.odin`
- [ ] Created `src/core/query_engine.odin`
- [ ] Created `ffi/tree_sitter/queries/memory_safety.scm`
- [ ] Gate M3.1 passed (5 checks)

### M3.2 — C002 SCM Migration
- [ ] Added `c002_scm_matcher` to `c002-COR-Pointer.odin`
- [ ] Shadow mode enabled in `main.odin`
- [ ] Zero parity failures on full corpus
- [ ] Manual C002 walker retired
- [ ] Gate M3.2 passed (4 checks)

### M3.3 — C003–C008 Real Implementation
- [ ] Created `ffi/tree_sitter/queries/naming_rules.scm`
- [ ] C003 (snake_case procs) implemented and tested
- [ ] C004 (private visibility) implemented and tested
- [ ] C005 (internal visibility) implemented and tested
- [ ] C006 (public doc comments) implemented and tested
- [ ] C007 (PascalCase types) implemented and tested
- [ ] C008 (acronym handling) implemented and tested
- [ ] 3 pass + 3 fail fixtures per rule
- [ ] Gate M3.3 passed

### M3.4 — Odin 2026 Migration Rules
- [ ] Created `ffi/tree_sitter/queries/odin2026_migration.scm`
- [ ] Created `src/core/c009-MIG-LegacyOS.odin`
- [ ] Created `src/core/c010-MIG-SmallArray.odin`
- [ ] C009 fires on `core:os/old`, SILENT on `core:os` (critical!)
- [ ] C010 fires on `Small_Array`, SILENT on `[dynamic; N]T`
- [ ] Gate M3.4 passed

### M4 — CLI Enhancements
- [ ] Created `src/core/config.odin` (TOML parser)
- [ ] `--help` flag working
- [ ] `--list-rules` flag working
- [ ] `--rule` filter working
- [ ] `--format json` working, valid JSON
- [ ] `odin-lint.toml` parsed and applied
- [ ] Gate 4 passed

### M4.5 — Autofix Layer
- [ ] Created `src/core/autofix.odin`
- [ ] `FixEdit` struct defined
- [ ] `--fix-dry-run` working
- [ ] `--fix` applies C001 correction correctly
- [ ] Re-lint after fix shows 0 violations
- [ ] Gate 4.5 passed

### M5 — OLS Plugin
- [ ] `odin_lint_analyze_file` returns real diagnostics
- [ ] Plugin builds without errors
- [ ] C001 diagnostic appears in editor
- [ ] Gate 5 passed

### M5.5 — MCP Gateway
- [ ] Created `src/mcp/` package
- [ ] Streamable HTTP server on `:6789`
- [ ] `server_card.json` at `.well-known/mcp`
- [ ] `run_lint_denoise` tool working
- [ ] `ols_export_symbols` tool working
- [ ] Connected to Claude Code (or other MCP client)
- [ ] Gate 5.5 passed

### M5.6 — DNA Impact Analysis
- [ ] Created `src/core/dna_exporter.odin`
- [ ] `--export-symbols` generates valid `symbols.json`
- [ ] `callers` and `callees` populated
- [ ] `memory_role` correctly classified
- [ ] `get_dna_context` MCP tool returning subgraph
- [ ] `run_lint_denoise` MCP tool returning structured JSON
- [ ] Gate 5.6 passed

---

## Appendix A — File Map: Before and After

```
BEFORE (current):                    AFTER (V7):

src/core/
  main.odin (295)              →     main.odin (400+, new flags + query init)
  tree_sitter_bindings.odin    →     tree_sitter_bindings.odin (+ query API)
  tree_sitter.odin             →     tree_sitter.odin (unchanged)
  query_engine.odin            →     [NEW] query_engine.odin
  c001-COR-Memory.odin         →     c001-COR-Memory.odin (minor: uses query)
  c002-COR-Pointer.odin        →     c002-COR-Pointer.odin (SCM matcher added)
  c003–c008 (stubs)            →     c003–c008 (real implementations)
  c009-MIG-LegacyOS.odin       →     [NEW]
  c010-MIG-SmallArray.odin     →     [NEW]
  suppression.odin             →     suppression.odin (unchanged)
  ast.odin                     →     ast.odin (unchanged)
  autofix.odin                 →     [NEW]
  dna_exporter.odin            →     [NEW]
  plugin_main.odin             →     plugin_main.odin (real implementation)
  config.odin                  →     [NEW]

  [DELETED]
  c002-COR-Pointer.odin.backup
  c002-COR-Pointer.odin.improved.re
  c002-COR-Pointer.odin.old
  main.odin.backup / .backup2
  odin_lint_plugin.odin (duplicate)

src/mcp/                       →     [NEW directory]
  mcp_server.odin
  mcp_tools.odin
  server_card.json

ffi/tree_sitter/queries/       →     [NEW directory]
  memory_safety.scm
  naming_rules.scm
  odin2026_migration.scm
  error_handling.scm           →     [for C201, M6]
  dod_patterns.scm             →     [for C101, M6]
```

---

## Appendix B — Rule ID Quick Reference

| ID | Category | Status | What It Detects |
|----|----------|--------|----------------|
| C001 | CORRECTNESS | ✅ Done | `make()`/`new()` without `defer free()` |
| C002 | CORRECTNESS | ✅ Done (being SCM-migrated) | `defer free()` called twice for same variable |
| C003 | STYLE | ⚠️ Stub → M3.3 | Proc names not `snake_case` |
| C004 | STYLE | ⚠️ Stub → M3.3 | Private procs without `_` prefix |
| C005 | STYLE | ⚠️ Stub → M3.3 | Internal proc visibility |
| C006 | STYLE | ⚠️ Stub → M3.3 | Public API procs without doc comment |
| C007 | STYLE | ⚠️ Stub → M3.3 | Type names not `PascalCase` |
| C008 | STYLE | ⚠️ Stub → M3.3 | Acronyms not treated as whole words |
| C009 | MIGRATION | ❌ New → M3.4 | `import "core:os/old"` (removed Q3 2026) |
| C010 | MIGRATION | ❌ New → M3.4 | `Small_Array(N, T)` (use `[dynamic; N]T`) |
| C101 | CORRECTNESS | ❌ Future (M6) | `context.allocator` changed without restore |
| C201 | CORRECTNESS | ❌ Future (M6) | Ignored error return (`_, _` pattern) |
| C202 | CORRECTNESS | ❌ Future (M6) | Incomplete `switch` over enum |

---

*Version: 1.0*
*Created: April 2026*
*Companion document: odin-lint-implementation-planV7.md*
