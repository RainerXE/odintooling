# odin-lint — Implementation Plan (v7)
*A Super Linter & Semantic Engine for the Odin Programming Language*
*Version 7.2 · April 2026 — SCM Query Architecture, AI Integration Layer, Semantic-Graph Agent Strategy & FFI Safety Rules*

---

## Table of Contents

1. [What Changed from V6](#1-what-changed-from-v6)
2. [Folder Structure](#2-folder-structure)
3. [AST Strategy](#3-ast-strategy)
4. [SCM Query Engine](#4-scm-query-engine)
5. [Migration Strategy: Manual → Query-Based](#5-migration-strategy-manual--query-based)
6. [FFI Integration](#6-ffi-integration)
7. [Testing](#7-testing)
8. [Build System](#8-build-system)
9. [Error Classification System](#9-error-classification-system)
10. [Future Vision: odintooling Suite](#10-future-vision-odintooling-suite)
11. [Milestones & Status](#11-milestones--status)
12. [Lessons Learned](#12-lessons-learned)
13. [Semantic-Graph Agent Strategy (V7.1)](#13-semantic-graph-agent-strategy-v71)

---

## 1. What Changed from V6

V7 adds two major architectural ideas on top of the solid V6 foundation.
Everything in V6 that works stays unchanged. The new elements are:

### New in V7

**SCM Query Engine (M3.1)**
Tree-sitter has a built-in S-expression query language (`.scm` files) that
replaces manual recursive AST walking. A query like:

```scheme
(call_expression
  function: (identifier) @fn
  (#match? @fn "^(make|new)$")) @allocation
```

replaces 80 lines of manual child traversal. The query engine is faster,
declarative, and shareable with editors that already use tree-sitter queries.
This is adopted for M3+ rules; C001 and C002 are migrated as a Shadow-and-Replace
exercise (both run in parallel, outputs compared, manual walker retired when parity
is confirmed).

**AI Export Layer (M5+)**
odin-lint becomes the ground-truth generator for AI tooling. A `dna_exporter.odin`
produces a structured `symbols.json` that describes procedure signatures, memory
allocation patterns, and lint results. This feeds a RAG pipeline and enables
AI agents to reason about an Odin codebase with semantic precision rather than
raw text.

### What Did NOT Change from V6

- Dual AST strategy (tree-sitter CLI / `^ast.File` OLS) — unchanged
- Milestone sequence M0–M5.5 — unchanged, new milestones appended after M5.5
- All completed milestones (M0, M1, M2) — status preserved
- V6 lessons learned — preserved and extended
- FixEdit autofix layer design — unchanged
- MCP Gateway design — unchanged, now gains the DNA export endpoint

### New in V7.1

**Semantic-Graph Agent Strategy (Section 13)**
A full AI integration strategy grounded in April 2026 model and tooling research.
Covers: Gemma 4 model selection, Odin-DNA hybrid graph-RAG architecture, MCP best
practices, LoRA fine-tuning approach, and the Incremental Denoising workflow.

**Odin 2026 Migration Rules (M3.4)**
Two concrete new rules targeting the April 2026 Odin language landscape:
- C009: Flag `import "core:os/old"` — the deprecated legacy os API, removed Q3 2026
- C010: Flag `Small_Array(N, T)` from `core:container/small_array` — superseded by the
  built-in `[dynamic; N]T` fixed-capacity array syntax shipped in dev-2026-04

**M5.6: DNA Impact Analysis**
Extends the DNA export layer with "Call Radius" extraction (callers + callees per
symbol) and vector embedding generation — producing a hybrid graph-RAG structure that
outperforms pure structural or pure semantic retrieval.

### New in V7.2

**C011: FFI Memory Safety Rule (M3.4)**
Derived from real bugs encountered during tree-sitter FFI integration. Three
patterns, all SCM-detectable, covering the C/Odin boundary: C strings used
without cloning (dangling pointer risk), C resource handles allocated without
a matching `defer ts_*_delete()` (leak), and C function return values used
without checking the error output parameter. Placed in M3.4 alongside the
Odin 2026 migration rules — same milestone, same SCM infrastructure.

### What Was Incorporated from the Addon Proposals

**Call Graph as SQLite backing store (M5.6):** The addon proposal's SQLite
schema (`functions`, `variables`, `usages`, `calls`) is a strong fit for the
DNA Impact Analysis milestone. Rather than keeping `symbols.json` as the only
persistent format, M5.6 now uses SQLite as the primary backing store for the
call graph — enabling SQL queries over the codebase graph (e.g. "find all
variables freed then used after free") without loading the entire graph into
memory. `symbols.json` remains the portable export format.

**`--explain` and `--refactor` CLI flags (M4 + M5.6):** The addon's `--explain`
and `--refactor` subcommands are real user value. `--explain <file:line>` is
added to M4 CLI enhancements as a local flag that describes *why* a rule fired.
`--refactor` maps to the `run_lint_denoise` MCP tool (M5.6) and is surfaced as
a CLI flag post-M5.6.

### What Was Rejected from the Addon Proposals

**`p_`, `pa_`, `_unsafe` pointer prefix conventions:** These are non-standard
Odin naming rules not used in the Odin core library, OLS, or any major Odin
project. Adding them as lint rules would generate enormous noise on real
codebases. If a user wants these conventions enforced, they belong in a
*configurable* rule file (future: `odin-lint.toml` custom rules), not as
built-in rules. Not adopted.

**`SAFE_ARRAY_ACCESS` macro and `NonNullPointer` wrapper type:** These are
user-defined constructs that do not exist in Odin's standard library. A lint
rule that flags array accesses for not using a non-existent macro would be
unusable on any real codebase. Not adopted.

**`_dangling` and `_oboe` naming conventions:** Same issue as above —
project-specific conventions with no grounding in the Odin ecosystem.
Not adopted.

### What Was Rejected from the V7 Draft

**C101 SOA hint as M4 scope** — deferred to M6. SOA analysis requires type-size
information that tree-sitter alone cannot provide. It needs either a custom Odin
type-size database or integration with the OLS type-checker. Not ready for M4.

---

## 2. Folder Structure

```
odin-lint/
├── artifacts/                    # Build outputs
├── build/                        # Odin-based build system
├── docs/
│   └── ODIN_STYLE_GUIDE_v2.md
├── ffi/
│   └── tree_sitter/
│       ├── tree-sitter-api.h
│       ├── tree_sitter.h
│       ├── tree-sitter-lib/           # submodule: tree-sitter runtime
│       │   └── tree-sitter-odin/      # submodule: Odin grammar
│       └── queries/                   # NEW (M3.1): SCM pattern files
│           ├── memory_safety.scm      # make/new/free/delete tracking
│           ├── naming_rules.scm       # snake_case, PascalCase
│           ├── error_handling.scm     # unchecked error returns
│           ├── ffi_safety.scm         # C string cloning, C handle cleanup (C011)
│           ├── odin2026_migration.scm # os/old imports + Small_Array usage (C009/C010)
│           └── dod_patterns.scm       # SOA / hot-cold field analysis (M6)
├── plans/
│   ├── odin-lint-implementation-planV7.md   # this file
│   ├── odin-lint-implementation-planV6.md   # previous version (reference)
│   ├── M3-implementation-v2.md
│   ├── odin-lint-ols-integration-plan.md
│   └── REF_AGENT_PROMPT_MILESTONE2.md
├── scripts/
│   ├── build.sh
│   ├── build_external_tree_sitter.sh
│   ├── build_plugin.sh
│   └── test_rules.sh
├── src/
│   ├── core/
│   │   ├── main.odin
│   │   ├── ast.odin
│   │   ├── tree_sitter.odin           # tree-sitter FFI bindings
│   │   ├── tree_sitter_bindings.odin
│   │   ├── query_engine.odin          # NEW (M3.1): SCM query wrapper
│   │   ├── suppression.odin
│   │   ├── c001.odin                  # C001 (tree-sitter manual path)
│   │   ├── c002.odin                  # C002 (tree-sitter manual path)
│   │   ├── autofix.odin               # FixEdit layer (M4.5)
│   │   ├── dna_exporter.odin          # NEW (M5+): symbols.json export
│   │   ├── plugin_main.odin
│   │   └── integration.odin
│   ├── rules/
│   │   └── correctness/
│   │       ├── c001.odin              # C001 (OLS/^ast.File path)
│   │       ├── c002.odin
│   │       └── ...c003-c008.odin
│   ├── mcp/                           # NEW (M5.5): MCP Gateway
│   │   ├── mcp_server.odin            # Streamable HTTP transport
│   │   ├── mcp_tools.odin
│   │   └── server_card.json           # .well-known capability discovery
│   ├── db/                            # NEW (M5.6): Call graph SQLite store
│   │   └── call_graph.odin            # Schema + query helpers
│   └── integrations/
│       └── ols/
├── tests/
│   ├── fixtures/
│   │   ├── pass/
│   │   └── fail/
│   └── real-world/
└── vendor/
    └── ols/
```

---

## 3. AST Strategy

*Unchanged from V6. Reproduced here for completeness.*

### Two Paths, Two AST Sources

```
┌─────────────────────────────────────────────────────┐
│  OLS Plugin path                                    │
│  Input:  ^ast.File  (from core:odin/ast)            │
│  Walk:   ast.walk() + ast.Visitor                   │
│  Rules:  src/rules/correctness/c001.odin etc.       │
│  When:   file opened/changed in editor              │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Standalone CLI path                                │
│  Input:  TSTree  (from tree-sitter via FFI)         │
│  Walk:   query_engine (M3.1+) or manual walker      │
│  Rules:  src/core/c001.odin etc.                    │
│  When:   odin-lint <file> from terminal / CI        │
└─────────────────────────────────────────────────────┘
```

The SCM query engine (M3.1) operates on the tree-sitter CLI path only.
The OLS plugin path continues to use `ast.walk()` on `^ast.File`.

---

## 4. SCM Query Engine

### Why SCM Queries

Manual AST walking (the V6 approach) works but has a cost: every rule is 60-120
lines of nested loop traversal. Tree-sitter's built-in S-expression query language
expresses the same pattern in 3-10 lines, executes in native C, and shares the
same syntax as Neovim/Helix treesitter queries — which means patterns can be
tested interactively before being wired into the linter.

### FFI Additions for the Query Engine

```odin
// src/core/tree_sitter_bindings.odin — additions for M3.1
foreign ts {
    // Query compilation
    ts_query_new :: proc(
        language:     rawptr,
        source:       cstring,
        source_len:   u32,
        error_offset: ^u32,
        error_type:   ^u32,
    ) -> rawptr ---
    ts_query_delete :: proc(query: rawptr) ---

    // Cursor for iterating matches
    ts_query_cursor_new     :: proc() -> rawptr ---
    ts_query_cursor_delete  :: proc(cursor: rawptr) ---
    ts_query_cursor_exec    :: proc(cursor: rawptr, query: rawptr, node: TSNode) ---
    ts_query_cursor_next_match :: proc(
        cursor: rawptr,
        match:  ^TSQueryMatch,
    ) -> bool ---

    // Capture info
    ts_query_capture_count     :: proc(query: rawptr) -> u32 ---
    ts_query_capture_name_for_id :: proc(
        query:      rawptr,
        id:         u32,
        length:     ^u32,
    ) -> cstring ---
}

TSQueryMatch :: struct {
    id:            u32,
    pattern_index: u16,
    capture_count: u16,
    captures:      ^TSQueryCapture,
}

TSQueryCapture :: struct {
    node:  TSNode,
    index: u32,
}
```

### query_engine.odin Interface

```odin
// src/core/query_engine.odin
QueryResult :: struct {
    captures: map[string]TSNode,  // capture name → matched node
    pattern:  int,                // which pattern in the SCM matched
}

// Load and compile a .scm file once; reuse the compiled query per file.
load_query :: proc(language: rawptr, scm_path: string) -> (rawptr, bool)

// Run a compiled query over a tree; return all matches.
run_query :: proc(
    query:      rawptr,
    root_node:  TSNode,
    file_lines: []string,
) -> []QueryResult
```

### memory_safety.scm (M3.2)

```scheme
; Capture every make() or new() call assigned to a local variable.
; @var_name = the LHS identifier
; @alloc    = the call_expression node
(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @fn
      (#match? @fn "^(make|new)$")))) @alloc

; Capture every defer free() or defer delete() call.
; @freed_var = the identifier being freed
(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var)))
```

### naming_rules.scm (M3.3)

```scheme
; Capture proc declarations — name must be snake_case.
(procedure_declaration
  name: (identifier) @proc_name)

; Capture type declarations — name must be PascalCase.
(type_declaration
  name: (identifier) @type_name)

; Capture struct field declarations.
(field_declaration
  name: (field_identifier) @field_name)
```

### error_handling.scm (C201, M4+)

```scheme
; Capture assignments that ignore an error return with blank identifier.
; Pattern: val, _ := some_proc()
(short_var_decl
  (identifier_list
    (identifier) @val
    (blank_identifier) @ignored_err)
  (expression_list
    (call_expression) @call))
```

---

## 5. Migration Strategy: Manual → Query-Based

This "Shadow-and-Replace" protocol is the safe way to adopt SCM queries
without breaking working rules.

### Phase A — SCM Parallelism (M3.1)

Implement `query_engine.odin` alongside the existing manual walker.
Run both for C001 on the same 1172-file test corpus.
Compare outputs. Any divergence is a bug — in the query, not the manual walker
(the manual walker is the known-good baseline).

### Phase B — Rule Struct Refactor (M3.2)

Extend the `Rule` struct to carry a compiled query reference alongside the
existing matcher proc:

```odin
Rule :: struct {
    id:            string,
    tier:          string,
    matcher:       proc(file_path: string, node: ^ASTNode) -> []Diagnostic,
    query_matcher: proc(result: QueryResult, file_path: string, lines: []string) -> []Diagnostic,
    // ... message, fix_hint unchanged
}
```

Rules can implement either or both. The engine calls `query_matcher` when a
compiled query is available and `matcher` as fallback.

### Phase C — Deprecation

Once SCM-based C001 and C002 match 100% accuracy on the test corpus,
delete the manual walker versions. The `.scm` file becomes the source
of truth for what the rule detects.

### Phase D — FixEdit Capture Binding (M4.5)

SCM captures bind directly to `FixEdit` generation. The `@var_name` capture
from `memory_safety.scm` gives the exact source range for "insert defer free
after this allocation" — no text scanning needed.

```odin
// From query result to fix:
fix_for_c001 :: proc(result: QueryResult) -> FixEdit {
    alloc_node := result.captures["alloc"]
    return FixEdit{
        start    = {line = alloc_node.end_point.row + 1, col = 0},
        end      = {line = alloc_node.end_point.row + 1, col = 0},
        new_text = fmt.aprintf("\tdefer free(%s)\n", result.captures["var_name"]),
    }
}
```

---

## 6. FFI Integration

*Unchanged from V6, extended with query API above.*

### tree-sitter Binding Plan (Core + Query)

```odin
// src/core/tree_sitter.odin — core bindings (unchanged from V6)
foreign import ts      "tree_sitter/libtree-sitter.a"
foreign import ts_odin "tree_sitter/libtree-sitter-odin.a"

TSNode  :: struct { ctx: [4]rawptr, id: rawptr }
TSPoint :: struct { row, column: u32 }

@(default_calling_convention = "c")
foreign ts {
    ts_parser_new          :: proc() -> rawptr ---
    ts_parser_delete       :: proc(parser: rawptr) ---
    ts_parser_set_language :: proc(parser: rawptr, lang: rawptr) -> bool ---
    ts_parser_parse_string :: proc(parser, old_tree: rawptr,
                                   src: cstring, len: u32) -> rawptr ---
    ts_tree_root_node      :: proc(tree: rawptr) -> TSNode ---
    ts_tree_delete         :: proc(tree: rawptr) ---
    ts_node_type           :: proc(node: TSNode) -> cstring ---
    ts_node_start_point    :: proc(node: TSNode) -> TSPoint ---
    ts_node_end_point      :: proc(node: TSNode) -> TSPoint ---
    ts_node_child_count    :: proc(node: TSNode) -> u32 ---
    ts_node_child          :: proc(node: TSNode, i: u32) -> TSNode ---
    ts_node_string         :: proc(node: TSNode) -> cstring ---
    ts_node_is_null        :: proc(node: TSNode) -> bool ---
    // Query API — see Section 4
    ts_query_new           :: proc(...) -> rawptr ---
    ts_query_delete        :: proc(q: rawptr) ---
    ts_query_cursor_new    :: proc() -> rawptr ---
    ts_query_cursor_delete :: proc(c: rawptr) ---
    ts_query_cursor_exec   :: proc(c, q: rawptr, node: TSNode) ---
    ts_query_cursor_next_match :: proc(c: rawptr, m: ^TSQueryMatch) -> bool ---
}
```

---

## 7. Testing

*Unchanged from V6.*

### Fixture Requirements (per rule)

- 3 `tests/fixtures/pass/<rule>/` — must produce zero diagnostics
- 3 `tests/fixtures/fail/<rule>/` — must produce exactly the documented diagnostic
- Snapshot: expected stdout for each fail fixture

### Real-World Testing Scope

| Rule | Odin core | Odin base | RuiShin | OLS |
|------|-----------|-----------|---------|-----|
| C001 | ✅ | ✅ | ✅ | ✅ |
| C002 | ❌ too noisy | ❌ | ✅ | ✅ |
| C003-C008 | ❌ different conventions | ❌ | ✅ | ✅ |

### False Positive Thresholds

- Correctness rules (C001, C002): < 5%
- Style/naming rules (C003-C008): < 10%
- Threshold exceeded → refine rule before proceeding to gate

### Query Parity Test (M3.1 specific)

When running SCM queries in parallel with the manual walker, parity is
defined as: identical rule_id, file, line, and column for every diagnostic.
Any divergence is logged to `tests/query_parity_report.txt` for investigation.

---

## 8. Build System

```makefile
build-cli:
    odin build src/core -out:artifacts/odin-lint

build-plugin:
    odin build src/core -build-mode:shared \
        -out:artifacts/odin-lint-plugin.dylib

build-ols:
    cd vendor/ols && ./build.sh

build-all: build-cli build-plugin build-ols

test:
    bash scripts/test_rules.sh

test-parity:
    bash scripts/test_query_parity.sh   # M3.1: compare SCM vs manual walker

clean:
    rm -f artifacts/odin-lint artifacts/odin-lint-plugin.dylib
```

---

## 9. Error Classification System ✅ COMPLETED

*Unchanged from V6.*

```odin
DiagnosticType :: enum {
    NONE,           // No issues found
    VIOLATION,      // Normal rule violation       🔴
    CONTEXTUAL,     // Context-dependent issue     🟡
    INTERNAL_ERROR, // Linter internal failure     🟣
    INFO,           // Informational message       🔵
}
```

| Type | Emoji | Action |
|------|-------|--------|
| VIOLATION | 🔴 | Developer should fix |
| CONTEXTUAL | 🟡 | Developer should review |
| INTERNAL_ERROR | 🟣 | Report to developers |
| INFO | 🔵 | FYI only |

---

## 10. Future Vision: odintooling Suite

The project is named **odintooling** because it represents a suite of tools:

1. **odin-lint** ✅ (current focus) — static analysis and linting
2. **odin-assist** 💡 (future) — interactive code assistance
3. **odin-metrics** 📊 (future) — code quality metrics
4. **odin-refactor** 🔄 (future, enabled by M5/M5.5) — automated refactoring

### AI Export Layer (M5+)

odin-lint becomes a ground-truth generator for AI tooling. After M5, the linter
has semantic knowledge of every procedure, allocation, and lint result in a
codebase. The `dna_exporter.odin` materialises this into `symbols.json`:

```json
{
  "schema": "odin-lint-symbols/1.0",
  "generated": "2026-04-10T12:00:00Z",
  "file": "src/core/main.odin",
  "procedures": [
    {
      "name": "check_block_for_c001",
      "line": 42,
      "signature": "(block: ^ASTNode, file_path: string) -> []Diagnostic",
      "memory_role": "borrower",
      "allocates": ["file_lines"],
      "frees": ["file_lines", "content"],
      "callers": ["analyze_file_c001", "run_all_rules"],
      "callees": ["is_allocation_assignment", "extract_lhs_name", "emit_diagnostic"],
      "call_depth": 2,
      "lint_violations": []
    }
  ]
}
```

The `symbols.json` is the structural half of a **hybrid graph-RAG index**.
An optional `--embed` flag (M5.6) generates vector embeddings alongside it,
forming a complete hybrid index where structural graph traversal and semantic
similarity search complement each other.

**How this feeds the AI pipeline:**

1. `symbols.json` structural graph: answers "find all procedures that allocate
   without freeing" by walking `callers`/`callees` and filtering on
   `lint_violations`
2. Vector embeddings (M5.6): answers "find code similar to this description"
   via semantic similarity
3. The `lint_violations: []` field is a quality signal — only clean, verified
   Odin code is used as AI training examples
4. The `memory_role` field teaches the model ownership semantics without
   requiring it to reverse-engineer them from source text

**What it is NOT:**
- Not a code signature or certification system
- Not a leaderboard or community ranking
- Not requiring a network connection or external service

### OLS/LSP Platform (M5+)

From M5 onward, odin-lint integrates with OLS via the Language Server Protocol.
LSP provides bidirectional edit capabilities (`workspace/applyEdit`, code actions).

This enables three capabilities:

1. **Autofix as LSP code actions**: lint rule fixes surfaced as editor quick-fixes
2. **Refactoring**: rename, extract proc, and Odin-specific refactors
3. **MCP gateway**: OLS-backed edit/lint/fix tools exposed to AI agents via MCP

---

## 11. Milestones & Status

### Milestone Sequence

```
M0   Foundation                          ✅ COMPLETE
M1   CLI Tree-sitter Integration         ✅ COMPLETE
M2   C001 Rule Implementation            ✅ COMPLETE
M3   C002 + C003-C008 Rules              🔄 IN PROGRESS
  M3.1  Query Engine Integration         🔧 INFRASTRUCTURE DONE — SCM BUG BLOCKING GATE
  M3.2  C002 via SCM                     ⬜ PLANNED (blocked on M3.1 gate)
  M3.3  C003-C008 Naming Rules           ⬜ PLANNED
  M3.4  Odin 2026 Migration + FFI Safety Rules ⬜ PLANNED
M4   CLI Enhancements                    ⬜ PLANNED
M4.5 Autofix Layer                       ⬜ PLANNED
M5   OLS Plugin Integration              ⬜ PLANNED
M5.5 MCP Gateway                         ⬜ PLANNED
M5.6 DNA Impact Analysis                 ⬜ PLANNED
M6   Extended Rules (C101, C201, C202)   ⬜ PLANNED
```

---

### Current State Assessment — April 11 2026

**Last reviewed:** April 11 2026 via full codebase audit.

#### What exists and compiles

| File | Status | Notes |
|------|--------|-------|
| `src/core/query_engine.odin` | ✅ Created | `load_query`, `run_query`, `free_query_results` all implemented |
| `src/core/tree_sitter_bindings.odin` | ✅ Updated | Query API added: `ts_query_new`, cursor API, `TSQueryError`/`TSQueryCapture`/`TSQueryMatch` |
| `ffi/tree_sitter/queries/memory_safety.scm` | ⚠️ Created but incomplete | See bug below |
| `src/core/c002-COR-Pointer.odin` | ✅ Updated | `c002_scm_matcher` added at line 424 |
| `src/core/main.odin` | ✅ Updated | Shadow mode wired and running |
| Build | ✅ Succeeds | Two macOS version warnings (harmless) |

#### Known Bug — M3.1 Gate Blocked

`memory_safety.scm` captures the cleanup function name but **not the variable
being freed**. The file currently reads:

```scheme
(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#eq? @cleanup_fn "free"))) @defer_free
```

`c002_scm_matcher` expects `result.captures["freed_var"]` but that capture does
not exist in the SCM. Every match immediately `continue`s at line 450:

```odin
freed_node, has_freed := result.captures["freed_var"]
if !has_freed { continue }   // ← always taken — SCM never returns freed_var
```

**Result:** SCM always returns 0 diagnostics. Shadow parity reports `0==0` on
every file — which looks like a pass but is a false positive (SCM is silently
broken, not genuinely matching the manual walker).

**Fix required:** Add the `@freed_var` argument capture to `memory_safety.scm`:

```scheme
(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var))) @defer_free
```

#### Secondary Issue — Shadow Mode Noise in All Builds

Shadow mode (`[SHADOW]` prints) runs in every build, not just debug. Every
`odin-lint` invocation currently emits ~10 lines of stderr noise:

```
[SHADOW] Starting shadow mode analysis...
[SHADOW] Reading file content...
...
[SHADOW] Shadow mode finished
```

The plan specified `when ODIN_DEBUG` guard. This needs to be applied.

#### Cleanup Still Pending

| File | Action Needed |
|------|--------------|
| `src/core/odin_lint_plugin.odin` | Delete — duplicate of `plugin_main.odin` |
| `src/core/odin_lint_plugin.odin-e` | Delete — editor backup |

#### Not Yet Started

C003–C008 (stubs), C009, C010, C011, `autofix.odin`, `config.odin`,
`dna_exporter.odin`, `src/mcp/`, `ffi/tree_sitter/queries/naming_rules.scm`,
`ffi/tree_sitter/queries/odin2026_migration.scm`.

---

### ⏭ Immediate Next Actions (in order)

1. **Fix `memory_safety.scm`** — add `@freed_var` argument capture (5-minute fix)
2. **Guard shadow mode** with `when ODIN_DEBUG` in `main.odin`
3. **Run real parity test** — rebuild debug, run `./scripts/run_c002_tests.sh`,
   confirm shadow reports actual match counts (not `0==0`)
4. **Delete cleanup files** — `odin_lint_plugin.odin` and `odin_lint_plugin.odin-e`
5. **Gate M3.1** — all four checks must pass before starting M3.2

---

### ✅ Milestone 0 — Foundation (COMPLETE)
- CLI skeleton, stub rule, test harness

### ✅ Milestone 1 — CLI Tree-sitter Integration (COMPLETE)
- TSNode as 24-byte value struct (critical fix)
- Real Odin file parsing via tree-sitter FFI

### ✅ Milestone 2 — C001 Rule Implementation (COMPLETE)
- Block-level allocation detection, 1172 files tested
- 133 violations found, assumed zero false positives

### 🔄 Milestone 3 — C002 + C003-C008 + Query Engine (IN PROGRESS)

#### 🔧 M3.1 — Query Engine Integration — INFRASTRUCTURE DONE, GATE BLOCKED

**Goal:** SCM query API working end-to-end, C002 running via SCM in shadow
mode with verified parity against the manual walker.

**Completed tasks:**
- ✅ `ts_query_new`, `ts_query_cursor_*`, `ts_query_capture_*` added to FFI bindings
- ✅ `TSQueryError`, `TSQueryCapture`, `TSQueryMatch` structs defined
- ✅ `query_engine.odin` implemented: `load_query`, `run_query`, `free_query_results`, `unload_query`
- ✅ `memory_safety.scm` created (partial — see bug)
- ✅ `c002_scm_matcher` implemented in `c002-COR-Pointer.odin` (line 424)
- ✅ Shadow mode wired into `main.odin` — query loaded and compared per run
- ✅ Build succeeds with all new code

**Remaining tasks (blocking the gate):**
- ❌ **Fix `memory_safety.scm`**: missing `@freed_var` capture — SCM always returns 0
  ```scheme
  ; Current (broken — no @freed_var):
  (defer_statement (call_expression
    function: (identifier) @cleanup_fn
    (#eq? @cleanup_fn "free"))) @defer_free

  ; Required fix:
  (defer_statement (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var))) @defer_free
  ```
- ❌ **Guard shadow mode with `when ODIN_DEBUG`** in `main.odin` — currently
  emits ~10 `[SHADOW]` debug lines to stderr on every production run
- ❌ **Run real parity test** after fix — build with `-debug`, run `run_c002_tests.sh`,
  confirm shadow reports actual counts, not spurious `0==0`
- ❌ **Add alloc captures** to `memory_safety.scm` for C001 shadow work (the
  `@var_name` / `@alloc` patterns from the plan — needed for future C001 SCM migration)

**Gate M3.1:**
- [ ] `memory_safety.scm` fixed — `@freed_var` capture present and compiling
- [ ] Shadow mode guarded by `when ODIN_DEBUG` (no `[SHADOW]` output in release builds)
- [ ] `run_query` returns non-zero captures on C002 double-free fixtures
- [ ] SCM C002 matches manual C002 count on full C002 test suite (22 fixtures)
- [ ] No `[shadow] FAIL` lines on RuiShin corpus run

#### ⬜ M3.2 — C002 via SCM Query

**Goal:** C002 double-free detection rewritten using SCM captures.
This replaces the manual scope-tracking approach with a query that
finds all `(defer_statement (call_expression ...))` nodes and groups
them by variable name.

**Gate M3.2:**
- [ ] C002 false positive rate < 5% on RuiShin
- [ ] C002 false positive rate < 5% on OLS codebase
- [ ] 3 pass + 3 fail fixtures all passing

#### ⬜ M3.3 — Naming Rules C003-C008

Rules implemented via `naming_rules.scm`. All share a single query
execution pass; logic procs check the captured name against the
appropriate convention.

| Rule | Pattern |
|------|---------|
| C003 | Proc names must be `snake_case` |
| C004 | Private procs must start with `_` or `@(private)` |
| C005 | Internal procs (`@(private="file")`) naming |
| C006 | Public API procs must have doc comments |
| C007 | Type names must be `PascalCase` |
| C008 | Acronyms in identifiers should be treated as words |

#### ⬜ M3.4 — Odin 2026 Migration Rules + FFI Safety (NEW in V7.1/V7.2)

**Context: three concrete rules that deliver immediate value in the April 2026
Odin landscape, all implementable with the SCM query engine and no type-system
dependency.**

**C009: Legacy OS API (`core:os/old`)**

As of Q1 2026, the `core:os2` migration is **complete**. The new API is simply
`core:os`. The old pre-2026 implementation now lives at `core:os/old` and will
be **removed in Q3 2026**. Any codebase still importing `core:os/old` is on
borrowed time.

> ⚠️ Important correction from earlier planning: the rule should NOT flag
> `import "core:os"` (that is the new correct API). It should flag
> `import "core:os/old"`. Do not invert this.

```scheme
; odin2026_migration.scm — C009
; Flag any import of the deprecated legacy os package.
(import_declaration
  path: (interpreted_string_literal) @import_path
  (#match? @import_path "\"core:os/old\"")) @legacy_os_import
```

Fix hint: "Replace `core:os/old` with `core:os`. The new API requires explicit
allocator parameters on all procedures that return allocated memory."

**C010: `Small_Array` Superseded by `[dynamic; N]T`**

`core:container/small_array.Small_Array(N, T)` is superseded by the built-in
`[dynamic; N]T` fixed-capacity array syntax (dev-2026-04). The new syntax is
idiomatic, stack-backed, and integrates with all standard dynamic array
procedures.

```scheme
; C010: Flag Small_Array type usage
(call_expression
  function: (selector_expression
    field: (field_identifier) @fn
    (#eq? @fn "Small_Array"))
  ) @small_array_usage
```

Fix hint: "Replace `Small_Array(N, T)` with `[dynamic; N]T`. Example:
`arr: Small_Array(8, int)` → `arr: [dynamic; 8]int`."

**C011: FFI Memory Safety**

Earned directly from the tree-sitter integration work. Three patterns, all
reliably detectable via SCM queries on the CLI path:

**Pattern 1 — C string used without cloning:**
```scheme
; Flag: string_from_null_terminated_ptr result used without clone()
(short_var_decl
  (identifier_list (identifier) @var)
  (expression_list
    (call_expression
      function: (selector_expression
        field: (field_identifier) @fn
        (#eq? @fn "string_from_null_terminated_ptr"))))) @c_string_assign
```
The captured `@var` is then checked: if no subsequent `strings.clone(@var)` or
`strings.clone_to_cstring(@var)` exists before the owning C resource is freed,
fire a violation.

Message: "C string pointer used directly — will become dangling when C resource is freed. Use `strings.clone()` to copy to Odin-owned memory."

Fix: `name := strings.clone(strings.string_from_null_terminated_ptr(raw_ptr))`

**Pattern 2 — C resource handle without paired cleanup:**
This is C001 applied to the FFI boundary. The existing `memory_safety.scm` can
be extended with a pattern for known C resource-returning functions:

```scheme
; Flag: ts_query_new / ts_parser_new / ts_query_cursor_new without matching delete
(short_var_decl
  (identifier_list (identifier) @handle)
  (expression_list
    (call_expression
      function: (identifier) @fn
      (#match? @fn "^ts_(query_new|parser_new|query_cursor_new)$")))) @c_alloc
```

Same escape hatch logic as C001: if a `defer ts_*_delete(@handle)` exists in the
same block, suppress. If the handle is returned, suppress.

Message: "C resource allocated without paired cleanup. Add `defer ts_*_delete(handle)` immediately after allocation."

**Pattern 3 — C function error output parameter ignored:**
```scheme
; Flag: ts_query_new called where error_type output is never read
(short_var_decl
  (identifier_list (identifier) @result)
  (expression_list
    (call_expression
      function: (identifier) @fn
      (#eq? @fn "ts_query_new")
      arguments: (argument_list
        (_) (_) (_)
        (unary_expression operator: "&" operand: (identifier) @err_offset)
        (unary_expression operator: "&" operand: (identifier) @err_type))))) @ts_query_call
```

After the capture, check whether `@err_type` appears in a subsequent conditional.
If not, fire a violation.

Message: "ts_query_new error output parameter not checked. Verify `error_type == .None` before using the returned handle."

**Design note:** Patterns 1 and 2 are reliable enough for VIOLATION tier. Pattern 3
is harder to check without dataflow analysis — start at CONTEXTUAL tier and
promote to VIOLATION once false positive rate is confirmed below 5%.

**Gate M3.4:**
- [ ] C009 fires on `import "core:os/old"`, silent on `import "core:os"`
- [ ] C010 fires on `Small_Array` usage, provides correct replacement syntax
- [ ] C011-P1 fires on `string_from_null_terminated_ptr` without `strings.clone`
- [ ] C011-P2 fires on `ts_*_new` without matching `defer ts_*_delete`
- [ ] C011-P3 fires (CONTEXTUAL) when `ts_query_new` error param not read
- [ ] C011 is silent on correctly written FFI code in `src/core/tree_sitter.odin`
- [ ] All rules: 3 pass + 3 fail fixtures each

**Gate 3 (full M3):**
- [ ] C002 FP rate < 5% documented
- [ ] C003-C008 implemented and tested
- [ ] C009-C010 Odin 2026 migration rules implemented
- [ ] C011 FFI safety rules implemented (P1, P2 at VIOLATION; P3 at CONTEXTUAL)
- [ ] All rules: 3 pass + 3 fail fixtures
- [ ] Manual walker retired for C001 and C002 (Phase C complete)
- [ ] Rule documentation template applied to all rules

---

### ⬜ Milestone 4 — CLI Enhancements

- `--help` and `--list-rules` flags
- `--rule C001,C002` filter
- JSON output (`--format json`)

**Gate 4:**
- [ ] All flags working
- [ ] JSON output valid against schema
- [ ] [ ] `--explain` produces human-readable output for every rule in M3

---

### ⬜ Milestone 4.5 — Autofix Layer

```odin
FixEdit :: struct {
    file:     string,
    start:    Position,
    end:      Position,
    new_text: string,
}
```

- `--fix` and `--fix-dry-run` flags
- C001 fix: insert `defer free(var)` after allocation
- SCM captures provide exact source range (Phase D binding)
- Fix generation tested: correct position, correct content

**Gate 4.5:**
- [ ] `FixEdit` generation layer working for C001
- [ ] `--fix` flag applies correct edit verified by re-lint
- [ ] SCM capture used for range — no text scanning

---

### ⬜ Milestone 5 — OLS Plugin Integration

- Rules via `^ast.File` path
- `publishDiagnostics` LSP notification
- `textDocument/codeAction` for FixEdit
- LSP integration test

**Gate 5:**
- [ ] Diagnostics appear in editor for all M3 rules
- [ ] Quick fixes available for C001 and C002
- [ ] LSP integration test passing

---

### ⬜ Milestone 5.5 — MCP Gateway

MCP tools exposing OLS-backed semantic editing to AI agents:

```
ols_get_symbol(file, symbol_name) -> {range, type, signature}
ols_apply_edit(file, range, new_text) -> {success, diagnostics}
ols_get_diagnostics(file) -> [{line, col, message, source, rule_id}]
ols_lint_fix(file, diagnostic_id) -> {applied_edits, result_diagnostics}
ols_rename(file, line, col, new_name) -> {files_changed}
ols_export_symbols(file) -> symbols_json   # NEW: AI Export Layer endpoint
```

The `ols_export_symbols` tool generates the `symbols.json` described in
Section 10, feeding Frejay's RAG pipeline on demand.

**Gate 5.5:**
- [ ] OLS subprocess managed by MCP gateway
- [ ] `ols_get_symbol` and `ols_apply_edit` working
- [ ] `ols_get_diagnostics` returns odin-lint diagnostics
- [ ] `ols_export_symbols` generates valid `symbols.json`
- [ ] Streamable HTTP transport (not stdio) for production use
- [ ] `server_card.json` at `.well-known/mcp` for capability discovery
- [ ] Integrated as Frejay `OdinEditTool` plugin

---

### ⬜ Milestone 5.6 — DNA Impact Analysis (NEW in V7.1)

*Prerequisite: Gate 5.5 (MCP gateway + symbols.json working)*

This milestone extends the DNA export layer from a flat structural graph into
a full hybrid graph-RAG index. Research consensus (Oct 2025): combining AST
structural graphs with vector embeddings improves factual correctness ~8% over
either approach alone.

#### What M5.6 Adds to `dna_exporter.odin`

**0. SQLite Call Graph Store**

The call graph is persisted to SQLite (`odin_lint_graph.db`) rather than
kept solely in `symbols.json`. This makes the graph queryable without loading
everything into memory — critical for large codebases.

```sql
CREATE TABLE functions (
    id      INTEGER PRIMARY KEY,
    name    TEXT NOT NULL,
    file    TEXT NOT NULL,
    line    INTEGER,
    role    TEXT   -- "allocator" | "deallocator" | "borrower" | "neutral"
);
CREATE TABLE calls (
    caller_id  INTEGER REFERENCES functions(id),
    callee_id  INTEGER REFERENCES functions(id),
    line       INTEGER
);
CREATE TABLE variables (
    id           INTEGER PRIMARY KEY,
    name         TEXT,
    type         TEXT,
    function_id  INTEGER REFERENCES functions(id)
);
CREATE TABLE usages (
    variable_id  INTEGER REFERENCES variables(id),
    line         INTEGER,
    kind         TEXT   -- "declare" | "read" | "write" | "free"
);
```

SQL enables queries that `symbols.json` cannot serve efficiently:
```sql
-- Dangling pointer candidates: freed then used after free
SELECT v.name, f.name as in_function
FROM variables v
JOIN usages free_use ON v.id = free_use.variable_id AND free_use.kind = 'free'
JOIN usages after_use ON v.id = after_use.variable_id
    AND after_use.line > free_use.line
    AND after_use.kind = 'read'
JOIN functions f ON v.function_id = f.id;
```

`symbols.json` remains the portable export format for AI tooling.
SQLite is the local query engine. Both are produced by `--export-symbols`.

**1. Call Radius Extraction**

For every exported symbol, compute:
- `callers`: list of procedures that call this symbol (impact radius)
- `callees`: list of procedures this symbol calls (dependency set)
- `call_depth`: shortest call chain from `main` to this symbol

This is the "Impact Radius" pattern from CodeGraph. It allows an AI agent to
answer "if I change `check_block_for_c001`, what else breaks?" without scanning
source code.

```json
{
  "name": "check_block_for_c001",
  "callers": ["analyze_file_c001", "run_all_rules"],
  "callees": ["is_allocation_assignment", "extract_lhs_name", "emit_diagnostic"],
  "call_depth": 2,
  "allocates": ["file_lines"],
  "frees": ["file_lines"],
  "lint_violations": []
}
```

**2. Memory Origin Tagging**

Tag each procedure with its allocator role:
- `"role": "allocator"` — the procedure creates and returns owned memory
- `"role": "deallocator"` — the procedure frees memory passed to it
- `"role": "borrower"` — uses memory without owning it
- `"role": "neutral"` — no memory involvement

This feeds C001 classification and teaches the AI model the ownership semantics
of each procedure before it writes code.

**3. Vector Embedding Generation (Optional, `--embed` flag)**

Generate a text embedding for each procedure's signature + doc comment + lint
results. Store in the `symbols.json` alongside structural data, or in a
companion `symbols.vec` file (sqlite-vec format).

This enables hybrid queries: `get_dna_context("procedures that allocate and are
called from main")` can be answered structurally; `get_dna_context("procedures
similar to this description")` uses vector similarity. Both are needed.

#### New MCP Tools for M5.6

```
get_dna_context(proc_name)      -> subgraph: callers + callees + memory role
get_impact_radius(proc_name)    -> all symbols transitively affected by change
find_allocators()               -> all procedures tagged "allocator" role
run_lint_denoise(code_snippet)  -> structured lint errors for AI to fix
```

The `run_lint_denoise` tool is the foundation of the Incremental Denoising
workflow (see Section 13).

**Gate 5.6:**
- [ ] Call radius (callers + callees) exported for all symbols
- [ ] Memory origin role tagged for all procedures
- [ ] `get_dna_context` MCP tool returns valid subgraph
- [ ] `run_lint_denoise` MCP tool runs linter on a snippet, returns JSON errors
- [ ] Optional `--embed` flag generates vector embeddings
- [ ] Tested: AI agent can navigate call graph without reading source files

---

### ⬜ Milestone 6 — Extended Rules (NEW in V7)

*Prerequisite: Gate 5 (OLS type information available)*

These rules require more than tree-sitter can provide alone.
They depend on OLS type resolution.

#### C101: Context Integrity

Flag procedures that change `context.allocator` (or `context.temp_allocator`)
but fail to restore it before returning, or that return pointers allocated on
`context.temp_allocator`.

Query foundation: `dod_patterns.scm`

```scheme
(procedure_declaration) @proc
; custom predicate: proc modifies context.allocator
; custom predicate: proc does not restore context.allocator on all paths
```

**Why deferred from M4:** Requires control-flow analysis across all return
paths, not just a single AST pattern. OLS's type checker provides this.

#### C201: Unchecked Result Guard

Flag ignored error returns (`val, _ := proc_call()` where the proc returns
an error type or `bool` ok).

Query foundation: `error_handling.scm` (already defined in Section 4).

Analytic step: after the SCM captures the `@ignored_err`, OLS type resolution
confirms the ignored value is an `Error` or `bool`-typed return.

#### C202: Switch Exhaustiveness

Flag `switch` statements over enum types that do not cover all cases
and have no `case:` fallthrough.

```scheme
(switch_statement
  init: (expression)
  body: (switch_body)) @switch
```

Analytic step: OLS resolves the switched type to an enum, compares covered
cases against the enum's member list.

**Gate 6:**
- [ ] C101 false positive rate < 5% on RuiShin
- [ ] C201 fires on unchecked error returns, silent on intentional ignores
- [ ] C202 fires on incomplete enum switches
- [ ] All rules: 3 pass + 3 fail fixtures

---

## 12. Lessons Learned

*V6 lessons preserved. Extended with query-architecture lessons.*

### From V6: C002 Comprehensive Redesign

1. **Architectural vision beats incremental fixes** — 27% fewer lines, 50% fewer AST traversals
2. **Merge related functions** — `is_defer_cleanup` + `extract_var_name_from_free` → single `c002_extract_defer_free_target`
3. **Remove noisy features** — reassignment detection removed (too many false positives from reslicing)
4. **Robust patterns** — nil guards, word boundary checks, proper scope tracking with `node.start_line`
5. **`fmt.aprintf` not `fmt.tprintf`** — fix strings in Diagnostics must outlive the call frame

### New for V7: Query Architecture

1. **SCM queries are cheaper to maintain than manual walkers** — a 5-line `.scm` pattern
   is easier to read, review, and extend than 80 lines of nested `for &child in node.children`

2. **Shadow-and-Replace is the safe migration path** — never delete the manual walker
   until the query output matches it exactly on the full test corpus

3. **Capture names are the interface** — use consistent capture names (`@var_name`,
   `@alloc`, `@freed_var`) across `.scm` files. These names become the keys in
   `QueryResult.captures` and the handles for `FixEdit` generation

4. **Queries compile once, run many times** — compile the query at startup and
   pass the compiled handle to every file analysis. Never compile per-file.

5. **AI export must be opt-in** — `symbols.json` generation is triggered by
   `--export-symbols` flag or the `ols_export_symbols` MCP tool. It is never
   generated automatically during normal lint runs (performance cost)

### New for V7.1: Semantic-Graph Agent

6. **The Odin os2 migration completed in Q1 2026 — update rule targets accordingly.**
   The deprecated legacy API is `core:os/old` (removal: Q3 2026). The current
   correct API is simply `core:os`. A lint rule that flags `import "core:os"` would
   fire on *correct* code. Always flag `core:os/old`, never `core:os`.

7. **Hybrid graph-RAG outperforms either approach alone** — structural AST graph
   (call graph, memory roles) answers relational queries; vector embeddings answer
   semantic similarity queries. The `symbols.json` + `--embed` combination is the
   target architecture. Do not build one without planning for the other.

8. **Model selection is a hardware decision, not a capability decision** — Gemma 4
   31B Dense and 26B MoE A4B are within ~2% of each other on coding benchmarks.
   Pick based on available unified memory, not benchmark chasing. The 26B MoE with
   TurboQuant is the practical default for most Apple Silicon setups.

9. **"Diffusion-style" is a useful metaphor, not a formal technique** — the
   lint-fix-verify cycle is an established agentic workflow (Devin, SWE-agent,
   Claude Code all use it). Do not conflate it with academic code diffusion models
   (CodeDiffuSe, DDPD) which are training-time architectures, not inference pipelines.
   Use the metaphor to explain the workflow; do not use it as a technical justification.

10. **Qwen3-Coder remains stronger for pure code generation at matched hardware cost**
    — if local Apple Silicon is constrained, Qwen3-Coder via cloud API is a better
    code generation backend than a quantized Gemma 4 on underpowered hardware.
    Fine-tune Gemma 4 locally; use Qwen3-Coder API for heavy generation tasks.

### New for V7.2: FFI Boundary Safety

11. **The C/Odin FFI boundary has distinct memory ownership rules** — three patterns
    have proven consistently dangerous in practice and are now codified as C011:
    - C strings from FFI are *views* into C-owned memory. They become dangling the
      moment the C resource is freed. Always `strings.clone()` before storing.
    - C resource handles (parsers, queries, cursors) follow the same pattern as
      Odin `make`/`new` — they need a `defer ts_*_delete()` immediately after
      creation, not at the end of a distant scope.
    - C functions that return results via output pointer parameters (like
      `ts_query_new`'s `error_type`) must have those parameters checked. Ignoring
      them is equivalent to ignoring an error return in Odin.

12. **Lint rules derived from real bugs in the project's own FFI code are the highest-
    quality rules** — they have zero false positives on the existing codebase (the
    correct code is already written), and they encode hard-won knowledge about a
    class of bugs that is genuinely hard to reason about without the rule.

---

## Gate Summary

| Gate | Milestone | Key criterion | Status |
|------|-----------|--------------|--------|
| 0 | Foundation | CLI skeleton, stub rule | ✅ |
| 1 | Tree-sitter | Real file parsing | ✅ |
| 2 | C001 | Real allocation detection, 1172 files | ✅ |
| 3.1 | Query Engine | SCM bug fixed, real parity on C002 suite | 🔧 |
| 3.2 | C002 via SCM | Manual walker retired, FP < 5% | ⬜ |
| 3.3 | C003-C008 | Naming rules implemented and tested | ⬜ |
| 3.4 | C009-C011 | Migration + FFI safety rules | ⬜ |
| 4 | CLI enhancements | --help, --list-rules, JSON output, --explain | ⬜ |
| 4.5 | Autofix | --fix flag, FixEdit + SCM capture binding | ⬜ |
| 5 | OLS plugin | Editor diagnostics + code actions | ⬜ |
| 5.5 | MCP gateway | Agent-driven semantic editing + symbol export | ⬜ |
| 5.6 | DNA Impact Analysis | Call radius + memory roles + hybrid graph-RAG | ⬜ |
| 6 | Extended rules | C101, C201, C202 via OLS type info | ⬜ |

---

## 13. Semantic-Graph Agent Strategy (V7.1)

*Validated against April 2026 model benchmarks, Odin language state, and
published research on code knowledge graph architectures.*

### 13.1 The Goal

Build the gold standard of **local** Odin coding support. By combining
odin-lint's semantic precision with a fine-tuned local model and a code
knowledge graph, the goal is to surpass frontier model performance on
Odin-specific tasks — not because the model is larger, but because it has
perfect context the frontier model lacks.

This is the Semantic-Graph Agent architecture: the AI operates on a structured
graph of the codebase rather than raw text, gains deep Odin knowledge through
fine-tuning, and is grounded by the linter so it cannot hallucinate ownership
patterns.

---

### 13.2 Model Selection: April 2026

Two viable local models, serving different hardware profiles:

#### Option A: Gemma 4 31B Dense (High-End, M3 Max 96GB)

| Property | Value |
|----------|-------|
| Architecture | Dense transformer, 31B parameters |
| Context window | 256k tokens |
| AIME 2026 (thinking mode) | 89.2% |
| LiveCodeBench v6 | 80.0% |
| Codeforces ELO | 2150 |
| MLX support | Day-0 via `mlx-community` (4-bit quantized) |
| LoRA fine-tuning | M3 Max 96GB minimum |
| License | Apache 2.0 |

The 89% AIME figure is real but requires **thinking mode enabled**. Without
thinking, scores drop substantially. For Odin fine-tuning, thinking mode is
the right default — Odin's memory ownership patterns reward step-by-step
reasoning.

#### Option B: Gemma 4 26B MoE A4B (Practical, M2 Pro 32GB+)

| Property | Value |
|----------|-------|
| Architecture | MoE, 26B total / 4B active per forward pass |
| Context window | 256k tokens |
| AIME 2026 (thinking) | 88.3% |
| LiveCodeBench v6 | 77.1% |
| MLX + TurboQuant | ~4x memory reduction; fits M2 Pro 32GB |
| LoRA fine-tuning | M2 Pro 32GB (4-bit) workable |
| License | Apache 2.0 |

The MoE variant is nearly as capable as the 31B Dense at a fraction of the
active memory cost. Recommended for most users. TurboQuant makes long-context
(256k) analysis practical.

#### Qwen3 as Cloud/Agentic Alternative

Qwen3-Coder 480B-A35B (35B active) achieves state-of-the-art on agentic
coding benchmarks and is purpose-built for code tasks. It surpasses Gemma 4
on pure code generation, but is not practical for local Apple Silicon
deployment at that scale. Use it as a cloud inference backend (Qwen API) when
local hardware is insufficient or for generating fine-tuning data. Qwen3-32B
Dense is the local-viable alternative for users without Apple Silicon.

#### Decision Rule

```
Hardware ≥ M3 Max 96GB?  → Gemma 4 31B Dense (--think flag for complex tasks)
Hardware ≥ M2 Pro 32GB?  → Gemma 4 26B MoE A4B (TurboQuant)
Cloud/GPU server?         → Qwen3-Coder 480B-A35B
```

---

### 13.3 The Odin-DNA Model: Hybrid Graph-RAG

Research consensus (Oct 2025): combining AST structural graphs with vector
embeddings improves factual correctness ~8% over either approach alone. The
`symbols.json` from M5 is the structural half; the `--embed` output from M5.6
is the semantic half. Together they form a hybrid graph-RAG index.

```
┌──────────────────────────────────────────────────┐
│  Query: "how does check_block_for_c001 work?"    │
│                                                  │
│  1. Structural lookup (symbols.json graph):      │
│     → node: check_block_for_c001                 │
│     → callees: [is_allocation_assignment, ...]   │
│     → memory_role: "borrower"                    │
│     → lint_violations: []                        │
│                                                  │
│  2. Semantic lookup (vector index):              │
│     → similar procs: [check_block_for_c002, ...] │
│                                                  │
│  3. Merge + rank → context budget filled         │
│     → send to Gemma 4 with structured context    │
└──────────────────────────────────────────────────┘
```

**Why this beats raw-text RAG for Odin:**
- The graph knows that `file_lines` is allocated in `check_block_for_c001` and
  freed in its caller — an embedding alone cannot express this
- The linter's `lint_violations: []` field provides a quality signal: training
  data with no violations is higher quality than violation-containing code
- The call radius lets the model navigate to relevant context without consuming
  the entire context window on irrelevant files

---

### 13.4 LoRA Fine-Tuning: "Verification over Generation"

The goal of fine-tuning is not to make the model write more Odin — it is to
make the model **check its own Odin output against lint rules before
presenting it**. This is "Verification over Generation."

#### Training Data Pipeline

```
1. Run: odin-lint --export-symbols <codebase>
       Produces: symbols.json with memory roles + lint_violations

2. Filter: Keep only procedures where lint_violations = []
           (clean, verified Odin code only)

3. Inject: Add symbols.json metadata as system context in training JSONL:
   {
     "system": "<odin_dna>{ callers, callees, memory_role, ... }</odin_dna>",
     "user":   "Write a procedure that reads a file and returns its lines.",
     "assistant": "// correct Odin with defer free..."
   }

4. Fine-tune: mlx-lm lora --model gemma4-26b-a4b --data odin_dna_train.jsonl
                           --num-layers 16 --batch-size 4 --iters 1000
```

#### What the LoRA Adapter Learns

- Odin-specific allocator patterns (`make` / `defer free` idioms)
- Memory ownership conventions (who owns, who borrows)
- Idiomatic use of the new APIs: `core:os` (not `core:os/old`), `[dynamic; N]T`
- Self-checking: model learns to run mental lint before emitting code

#### Hardware

```
Gemma 4 26B MoE A4B + LoRA (16 layers):
  → ~16.3M trainable parameters (0.053% of total)
  → M2 Pro 32GB workable with 4-bit quantization
  → Training: ~1000 iters, estimated hours not days

Gemma 4 31B Dense + LoRA:
  → M3 Max 96GB minimum
  → Larger capacity for reasoning, slower to iterate
```

---

### 13.5 The Incremental Denoising Workflow

The lint-fix-verify cycle is an established agentic workflow pattern (used in
Devin, SWE-agent, Claude Code). The "diffusion" framing is a useful analogy —
the linter identifies "noise" (violations), the AI performs "denoising" (fixes)
in small verifiable steps — but it is an informal metaphor, not a formal
technique. Do not conflate it with the academic code diffusion models
(CodeDiffuSe, DDPD) which are training-time architectures.

```
┌─────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Write  │───▶│  odin-lint scan  │───▶│  AI denoises    │
│  draft  │    │  (noise signal)  │    │  flagged lines  │
└─────────┘    └──────────────────┘    └────────┬────────┘
     ▲                                          │
     │            ┌──────────────────┐          │
     └────────────│  Verify: 0 errors│◀─────────┘
                  └──────────────────┘
```

**Each cycle is small and verifiable.** The AI never rewrites large blocks; it
fixes exactly the lines flagged by the linter. The linter's structured JSON
output (`--format json`) is the feedback signal. After each fix, the linter
runs again to confirm no regressions.

**The `run_lint_denoise` MCP tool** (M5.6) makes this programmable: an AI
agent can call it in a loop, converging toward 0 violations without human
intervention.

---

### 13.6 MCP Architecture: April 2026 Best Practices

MCP is now a Linux Foundation standard (adopted by Anthropic, OpenAI, Google,
Microsoft). 97M+ monthly SDK downloads. Key architectural decisions for the
odin-lint MCP server:

| Decision | Choice | Reason |
|----------|--------|--------|
| Transport | Streamable HTTP | Scales across processes; required for production |
| Discovery | `server_card.json` at `.well-known/mcp` | Standard discoverability |
| Tool scope | Single-responsibility per tool | MCP best practice; easier to test |
| Auth | Local-only (no credentials) | Personal dev tool; no multi-tenant |
| Tool schemas | Strictly typed JSON Schema | Required by MCP conformance test suite |

**Tool surface for odin-lint MCP server:**

```
get_dna_context(proc_name)        → subgraph: callers + callees + memory role
get_impact_radius(proc_name)      → all transitively affected symbols
find_allocators()                 → all "allocator"-role procedures
run_lint_denoise(code: string)    → structured JSON violations for AI to fix
ols_get_symbol(file, symbol)      → {range, type, signature} from OLS
ols_apply_edit(file, range, text) → apply edit, return result diagnostics
ols_get_diagnostics(file)         → all lint diagnostics for file
ols_export_symbols(file)          → symbols.json for a file
```

The server exposes exactly what an AI coding agent needs to navigate the
codebase structurally, execute lint analysis, and apply verified fixes.

---

*Version: 7.2*
*Last status review: April 11 2026*
*Previous version: odin-lint-implementation-planV6.md (V7.0 was the internal draft)*
