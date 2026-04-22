# odin-lint — Implementation Plan (v7)
*A Super Linter & Semantic Engine for the Odin Programming Language*
*Version 7.5 · April 2026 — SCM Query Architecture, AI Integration Layer, Semantic-Graph Agent Strategy & FFI Safety Rules*

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
14. [Analysis Scope Model](#14-analysis-scope-model)

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

### Rule Tiers

| Tier | Rules | Default | Notes |
|------|-------|---------|-------|
| `correctness` | C001, C002, C011 | always-on | Definite bugs |
| `migration` | C009, C010 | always-on (warn) | Deprecation migrations — matches Ruff's `pyupgrade` category |
| `style` | C003-C008 | always-on | Naming conventions |
| `semantic` | C012, C101, C201, C202 | opt-in | Type-gated, requires OLS or flag |

The `migration` tier is new in V7.2. Rules like C009 (`core:os/old`) and C010
(`Small_Array`) are not style violations and not correctness bugs — they are
time-bounded deprecation migrations. Treating them as a distinct tier allows:
- Suppressing them for projects intentionally targeting older Odin versions
- CI pipelines that want to error on `correctness` but only warn on `migration`
- Clear documentation: "this code will stop compiling in Q3 2026"

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
M3   C002 + C003-C008 Rules              ✅ COMPLETE
  M3.1  Query Engine Integration         ✅ COMPLETE (April 12 2026)
  M3.2  C002 via SCM                     ✅ COMPLETE (April 12 2026)
  M3.3  C003-C008 + C012 Naming Rules    ✅ COMPLETE (April 13 2026)
  M3.4  Odin 2026 Migration + FFI Safety Rules ✅ COMPLETE (April 13 2026)
  M3.5  Embed SCM files at compile time       ✅ COMPLETE (April 13 2026)
M4   CLI Enhancements                    ✅ COMPLETE (April 13 2026)
  M4.0  Targets + Core CLI + odin-lint.toml domains ✅ COMPLETE (April 13 2026)
  M4.1  Output Formats + Explain        ✅ COMPLETE (April 13 2026)
M4.5 Autofix Layer                       ✅ COMPLETE (April 13 2026)
M5   OLS Plugin Integration              ✅ COMPLETE (April 18 2026)
M5.5 MCP Gateway                         ✅ COMPLETE (April 18 2026)
M5.6 DNA Impact Analysis + Code Graph    ✅ COMPLETE (April 19 2026)
M6   Extended Rules + Refactoring        🔧 IN PROGRESS
  C016 STY-LocalNaming (snake_case locals)        ✅ COMPLETE (April 20 2026)
  C017 STY-GlobalNaming (camelCase globals)       ✅ COMPLETE (April 20 2026)
  C018 STY-ProcVisibility (visibility naming)     ✅ COMPLETE (April 20 2026)
  C016–C018 per-rule toml opt-in/opt-out          ✅ COMPLETE (April 20 2026)
  C014 DEA-UnusedProc (dead private procs)        ✅ COMPLETE (April 20 2026)
  C015 DEA-UnusedConst (dead private consts/vars) ✅ COMPLETE (April 21 2026)
  C020 STY-ShortName (short var/param names)      ✅ COMPLETE (April 21 2026)
  C013 DEA-UnusedImport                           ⬜ SKIPPED (Odin compiler catches this)
  C012-T type-gated semantic naming               ⬜ PLANNED
  C019 type marker suffixes                       ⬜ BLOCKED (conventions need discussion)
  rename_symbol MCP tool                          ⬜ PLANNED
  LSP Call Hierarchy                              ⬜ PLANNED
M6.5 Structural Rules (B-category)      ✅ COMPLETE (April 21 2026)
  B001 Unmatched Brace / Unclosed Block            ✅ COMPLETE (April 21 2026)
M6.6 C001 False Positive Reduction (AST layer)   ✅ COMPLETE (April 21 2026)
  Tier 1: fix has_allocator_arg, context.allocator detection, multi-line make ✅
  Tier 2: _init proc name heuristic                                            ✅
  Tier 2b: fix is_free_call / has_manual_cleanup (direct delete detection)     ✅
  Remaining C001 FPs deferred — require package-scope or return-type info (M6.9/M7)
M6.7 C019 STY-TypeMarker                           ⬜ DEFERRED → post-C012 Phase 2 (M7.1+)
M6.9 Package-Scope Linting Foundation             ⬜ NEXT
  Define four analysis scopes (see Section 14)
  Group files by package (directory + matching package declaration)
  B002 STR-PackageName: file has wrong package declaration (majority wins)
  B003 STR-SubfolderPackage: subfolder shares package name with parent
M7   Graph Enrichment for LLM Tooling + Refactoring  ⬜ PLANNED
  Proper variable indexing (top-level only, memory_role for Allocator-typed)
  Proc return-type tracking in graph (enables allocator-return detection)
  Enrich get_dna_context MCP tool with variable roles
  C012-T unlock (shares memory_role infrastructure)
  Incremental graph rebuild: file-hash cache + eviction (--export-symbols fast path)
  ↳ Requires M6.9 package-scope foundation + M5.6 graph DB
M7.1 OLS Refactoring + Advanced Rules             🔄 IN PROGRESS (April 21 2026)
  ✅ C012-T1: explicit mem.Allocator var naming (fired when name lacks alloc/allocator)
  ✅ C012-T3: allocator-return without _owned (graph-enriched, needs memory_role DB)
  ✅ rename_symbol MCP tool (find_all_references → FixEdit set) — COMPLETE in M6
  ✅ LSP Call Hierarchy (VS Code "Show Call Hierarchy" on Odin procs) — COMPLETE April 22 2026
  ✅ C101 Context Integrity (context.allocator assigned without defer restore) — COMPLETE April 22 2026
  ⬜ C201 Unchecked Result Guard (ignored error returns)
  ⬜ C202 Switch Exhaustiveness (incomplete enum switches)
  ⬜ C019 STY-TypeMarker (BLOCKED until C012 Phase 2 + convention agreement)

M8 Frejay / Agent Integration API                 ⬜ PLANNED (after M7.1)
  ↳ Prerequisite: M7.1 complete; Frejay v0.1 stable enough to test against
  Gap 1 — errorClass field in JSON output
    Add errorClass to --format json (and new --format frejay alias)
    Taxonomy: correctness_memory_leak, correctness_double_free, ffi_resource_leak,
    migration_deprecated_import, migration_deprecated_fmt, style_naming_proc,
    style_naming_type, style_naming_local_var, style_naming_pkg_var,
    style_naming_visibility, style_ownership_naming, dead_code_unused_proc,
    dead_code_unused_const, structure_unmatched_brace, structure_package_name,
    structure_subfolder_clash. Format: {tier}_{category}_{detail}, 1:1 with rule IDs.
  Gap 2 — compile_check: OUT OF SCOPE for odin-lint (lives in Frejay OdinCompilerVerifier
    via VProcessService; odin-lint has no odin build integration)
  Gap 3 — Schema version contract
    Add "schema_version": "odin-lint-symbols/1.1" to symbols.json root
    Advertise in server_card.json at .well-known/mcp
    Bump minor version on any breaking graph schema change going forward
  Gap 4 — lint_workspace(path, rules?) batch MCP tool
    Run full lint scan on a directory; return all diagnostics as single JSON array
    Schema: [{file, rule_id, error_class, tier, line, col, message, fix_hint}]
    Essentially: odin-lint ./src/ --format json surfaced over MCP
    Critical for Frejay ExperienceStore bulk trace collection (D-68)
  Gap 5 — list_rules() MCP tool
    Return full rule catalog: id, tier, error_class, description, fix_hint, enabled_by_default
    Lets Frejay RuleInjectionPolicy (D-59) bootstrap from odin-lint's own catalog
  LSP parity — get_callers(name) + get_callees(name) dedicated MCP tools
    Currently only available bundled in get_dna_context; agents need targeted queries
    Backed by existing graph_get_callers / graph_get_callees in call_graph.odin
```

---

### Current State Assessment — April 13 2026

**Last reviewed:** April 13 2026. M3.1–M3.5 complete. All SCM rules embedded; binary is self-contained. Starting M4.

#### What exists and compiles

| File | Status | Notes |
|------|--------|-------|
| `src/core/query_engine.odin` | ✅ Complete | `load_query_src`, `run_query`, `free_query_results`, `unload_query` |
| `src/core/embedded_queries.odin` | ✅ Complete | `#load` constants for all 5 SCM files (M3.5) |
| `src/core/tree_sitter_bindings.odin` | ✅ Complete | Full query API + `ts_node_parent` for scope walking |
| `ffi/tree_sitter/queries/memory_safety.scm` | ✅ Complete | Captures `@freed_var` + `@cleanup_fn` for both plain and qualified calls |
| `ffi/tree_sitter/queries/naming_rules.scm` | ✅ Complete | C003 `@proc_name`, C007 `@struct_name`/`@enum_name` captures |
| `src/core/c002-COR-Pointer.odin` | ✅ Rewritten | Manual walker deleted; SCM-only implementation (157 lines) |
| `src/core/c003-STY-Naming.odin` | ✅ Rewritten | Real implementation; `naming_scm_run` handles C003+C007 in one pass |
| `src/core/c004-STY-Private.odin` | ✅ Stub | Clean deferred stub — no dead code |
| `src/core/c005-STY-Internal.odin` | ✅ Stub | Clean deferred stub — no dead code |
| `src/core/c006-STY-Public.odin` | ✅ Stub | Clean deferred stub — no dead code |
| `src/core/c007-STY-Types.odin` | ✅ Stub | Logic lives in `naming_scm_run` (c003) |
| `src/core/c008-STY-Acronyms.odin` | ✅ Stub | Clean deferred stub — no dead code |
| `src/core/main.odin` | ✅ Updated | C002 and C003+C007 use SCM production paths |
| Build | ✅ Succeeds | Two harmless macOS version warnings |

#### M3.1 Gate — PASSED ✅

- `memory_safety.scm`: `@freed_var` and `@cleanup_fn` captures present, compiling
- Shadow mode guarded by `when ODIN_DEBUG` (silent in release)
- `run_query` returns correct match counts
- RuiShin corpus: all 263 files parity OK (after block-scope fix)

#### M3.2 Gate — PASSED ✅

- Manual walker deleted (387 lines removed)
- SCM matcher is production C002
- Block-level scope key eliminates cross-branch false positives
- RuiShin: **0 C002 false positives** across 263 files
- All false-positive fixtures: 0 violations
- Known limitation: cross-block double-frees (defer in inner block + outer block) not detected — acceptable trade-off for precision

#### ⏭ Immediate Next Actions

1. **M3.3** — implement C003–C008 naming rules via `naming_rules.scm`
2. **M3.4** — C009, C010, C011 (Odin 2026 + FFI safety)
3. Cleanup: delete `odin_lint_plugin.odin` and `odin_lint_plugin.odin-e`

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

#### ✅ M3.1 — Query Engine Integration — COMPLETE (April 12 2026)

- TSNode ABI fixed: `ctx: [4]u32` (was `[4]rawptr` — 32 vs 48 bytes)
- `memory_safety.scm`: captures `@freed_var` + `@cleanup_fn`, handles plain and qualified calls
- `query_engine.odin`: `load_query`, `run_query`, `free_query_results`, `unload_query`
- Shadow mode guarded by `when ODIN_DEBUG`
- RuiShin corpus (263 files): all parity OK after block-scope fix

#### ✅ M3.2 — C002 via SCM Query — COMPLETE (April 12 2026)

- Manual walker (c002Matcher + C002AnalysisContext) deleted — 387 lines removed
- `c002_scm_matcher` is production C002; uses block-level scope key via `ts_node_parent`
- `ts_node_parent` binding added to `tree_sitter_bindings.odin`
- RuiShin: **0 false positives** across 263 files
- Known limitation: cross-block double-frees not detected (precision trade-off)

#### ✅ M3.3 — Naming Rules C003-C008 + C012 — COMPLETE (April 13 2026)

| Rule | Status | Implementation |
|------|--------|----------------|
| C003 | ✅ Live | `naming_rules.scm` `@proc_name` + `naming_scm_run` |
| C004 | ✅ Stub | Deferred to M3.4+ (visibility attribute handling) |
| C005 | ✅ Stub | Deferred to M3.4+ |
| C006 | ✅ Stub | Deferred to M3.4+ |
| C007 | ✅ Live | `naming_rules.scm` `@struct_name`/`@enum_name` + `naming_scm_run` |
| C008 | ✅ Stub | Deferred to M3.4+ |
| C012 | ✅ Live (opt-in) | `c012_rules.scm` + `c012_scm_run`; enabled via `--enable-c012` |

C012 sub-rules implemented (M3.3 syntactic phase):
- **S1**: `make`/`new` assignment without `_owned` suffix → INFO
- **S2**: slice expression without `_view`/`_borrowed` suffix → INFO
- **S3**: known allocator calls without `alloc`/`allocator` in name → INFO
- **S4**: Arena type declarations deferred to M6 (requires type annotation matching)

Key insight: `:=` inside procedure bodies is `assignment_statement` in Odin grammar,
NOT `variable_declaration` (which is only used at package scope).

Gate M3.3 results:
- C003: 3 violations detected on fixture; clean code silent; 84 violations in RuiShin
- C007: 2 violations detected on fixture; clean code silent; 67 violations in RuiShin
- C012: 5 INFO hits on violations fixture; clean fixture silent; default-off confirmed

#### ✅ M3.4 — Odin 2026 Migration Rules + FFI Safety — COMPLETE (April 13 2026)

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
- [ ] C011 FFI safety rules implemented (P2 at VIOLATION; P1/P3 deferred to M6)
- [ ] All rules: 3 pass + 3 fail fixtures
- [ ] Manual walker retired for C001 and C002 (Phase C complete)
- [ ] Rule documentation template applied to all rules
- [ ] SCM files embedded at compile time (M3.5) — binary is self-contained

---

#### ✅ M3.5 — Embed SCM files at compile time — COMPLETE (April 13 2026)

**Rationale:** Every new rule requires new Odin handler code alongside the SCM
pattern — recompile is unavoidable. Runtime-loading `.scm` files from relative
paths adds deployment complexity (binary only works from repo root) with zero
benefit over compile-time embedding.

**Implementation:**
1. Add `load_query_src` variant to `query_engine.odin` — takes SCM content as
   `string` instead of a file path
2. Create `src/core/embedded_queries.odin` — one `#load` constant per SCM file:
   ```odin
   MEMORY_SAFETY_SCM :: #load("../../ffi/tree_sitter/queries/memory_safety.scm", string)
   NAMING_RULES_SCM  :: #load("../../ffi/tree_sitter/queries/naming_rules.scm",  string)
   C012_RULES_SCM    :: #load("../../ffi/tree_sitter/queries/c012_rules.scm",     string)
   ODIN2026_SCM      :: #load("../../ffi/tree_sitter/queries/odin2026_migration.scm", string)
   FFI_SAFETY_SCM    :: #load("../../ffi/tree_sitter/queries/ffi_safety.scm",     string)
   ```
3. Update all `load_query(lang, "path/...")` call sites in `main.odin` to
   `load_query_src(lang, CONSTANT_NAME)`
4. Remove the file-path variant — no half-measures

**Gate M3.5:** ✅ ALL PASSED
- [x] `./artifacts/odin-lint <file>` works from any directory
- [x] No `.scm` files required at runtime
- [x] Build succeeds; all existing rule tests still pass

---

### ⬜ Milestone 4 — CLI Enhancements

Split into two sub-milestones to keep scope manageable.

#### ⬜ M4.0 — Targets + Core CLI

**Targets:**
- Single file: `odin-lint file.odin`
- Directory (recursive by default): `odin-lint ./src/`
  - Prints a warning when scanning recursively: `"Warning: scanning recursively — use --non-recursive to scan top-level only"`
  - `--non-recursive`: scan only the top-level directory, no subdirectories
  - Skips `vendor/` directories by default
  - `--include-vendor`: opt-in to include `vendor/` in the scan

**Flags:**
- `--version`: prints `odin-lint <version>` + `supports Odin dev-2026-04 (grammar: <hash>)`
- `--help`: full usage text listing all rules, flags, and examples
- `--list-rules`: machine-readable rule list (id, tier, message, one per line or JSON)
- `--rule C001,C002`: run only the specified rules (comma-separated)
- `--tier correctness|style`: run only rules of the given tier

**odin-lint.toml — Linter Domains (inspired by Biome v2)**

Rather than always-on rules that generate noise, project-specific rule sets are
activated via `[domains]` in `odin-lint.toml`. This pattern comes from Biome's
"linter domains" feature (shipped June 2025) and eliminates the need to manually
enable/disable groups of related rules.

```toml
[domains]
ffi        = true   # enables C011 FFI safety rules (auto if ffi/ dir detected)
odin_2026  = true   # enables C009 (os/old), C010 (Small_Array) migration rules
semantic_naming = false  # enables C012 (opt-in, default off)

[target]
odin_version = "dev-2026-04"   # suppresses migration rules for older targets
```

Domain detection heuristics (when `odin-lint.toml` is absent or has no `[domains]`):
- If `ffi/` directory exists at project root: `ffi = true` automatically
- If `odin_version` is unset: migration rules fire with a CONTEXTUAL note

**Output:**
- Exit codes: `0` = clean, `1` = violations found, `2` = internal error
- Summary line at end: `X violation(s) in Y file(s)`
- `"Starting odin-lint"` banner removed from normal output

**Gate M4.0:**
- [ ] `odin-lint ./src/` scans all `.odin` files recursively with warning
- [ ] `--non-recursive` limits scan to top level
- [ ] `vendor/` skipped by default; `--include-vendor` re-enables it
- [ ] `--version` prints version + grammar info
- [ ] `--rule C001` runs only C001; `--tier style` runs only style rules
- [ ] Exit code `1` when violations found, `0` when clean
- [ ] `[domains]` config activates/suppresses correct rule groups
- [ ] `ffi` domain auto-detected from `ffi/` directory presence
- [ ] Summary line printed after all files processed
- [ ] Our codebase: `0` violations, exit code `0`

---

#### ⬜ M4.1 — Output Formats + Explain

- `--format text` (default, current behaviour)
- `--format json`: JSON array of diagnostics — schema:
  ```json
  [{"file":"...","line":1,"column":1,"rule":"C001","tier":"correctness","message":"...","fix":"..."}]
  ```
- `--format sarif`: SARIF 2.1.0 for GitHub Actions / VS Code Problems panel
- `--explain C011`: static rule documentation — rationale, what triggers it,
  annotated code examples (pass + fail), how to fix

**Gate M4.1:**
- [ ] `--format json` output is valid JSON, passes schema check
- [ ] `--format sarif` output is SARIF 2.1.0 — accepted by GitHub Actions problem matcher
- [ ] `--format sarif` accepted by VS Code Problems panel
- [ ] `--explain <rule_id>` works for every rule in C001–C012
- [ ] `--explain` for unknown rule prints clear error, exits `2`

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

- `--fix`: apply fixes in-place (writes files) — safe mechanical transforms only
- `--unsafe-fix`: apply fixes that change API surface (e.g. C009 os2 migration
  where the new `core:os` API differs from `core:os/old`). Requires explicit
  opt-in; inspired by Ruff's `--unsafe-fix` distinction.
- `--propose`: dry-run — prints before/after diff for each fixable violation without writing
- C001 fix: insert `defer free(var)` after allocation
- SCM captures provide exact source range (Phase D binding)

**Gate 4.5:**
- [ ] `FixEdit` generation layer working for C001
- [ ] `--fix` flag applies correct edit verified by re-lint
- [ ] `--propose` shows before/after diff, no files written
- [ ] SCM capture used for range — no text scanning

---

### ✅ Milestone 5 — OLS Plugin Integration — COMPLETE (April 18 2026)

**Architecture decision (April 17 2026):** Rather than building a second AST-based
pipeline using `^ast.File`, M5 reuses the existing tree-sitter rule matchers (C001–C011)
via the in-memory document text provided by OLS. This avoids duplicating all rules,
ships faster, and keeps the linting behaviour identical between CLI and editor.

The `SemanticContext` / `^ast.File` path originally planned here is deferred to M6
for type-gated rules (C012) which genuinely need OLS type resolution.

#### What was built (April 17 2026)

**OLS plugin system** (`vendor/ols/src/server/plugin.odin` — new, all changes in OLS fork):
- `OLSPlugin` C-ABI interface with capability flags, lifecycle, and merge-all hooks
- Plugin registry: `plugin_registry_init` / `plugin_registry_shutdown`
- `plugin_run_diagnostics` — called on file open and save; zero cost when no plugins loaded
- `plugin_run_code_actions` — appended to `get_code_actions` result
- 6 OLS files modified; full changelog in `plans/plugin-interface-spec.md`

**odin-lint plugin** (`src/core/plugin_main.odin` — replaced):
- Exports `ols_plugin_get :: proc "c" () -> ^OLSPluginDescriptor`
- `init`: initialises tree-sitter parser once; refuses load on API version mismatch
- `on_diagnostics`: runs all rules (C001–C011) against in-memory editor text
- `free_result`: heap-frees list, items array, and all message cstrings
- Build: `./scripts/build_plugin.sh` → `artifacts/odin-lint-plugin.dylib`

#### Additional work completed (April 18 2026)

- [x] **Build and smoke-test**: `./scripts/build_plugin.sh` succeeds; no linker errors
- [x] **OLS build fix**: `filepath.replace_separators` → `filepath.replace_path_separators` across 21 call sites (Odin 2026-04 API change)
- [x] **Dylib crash fix**: Odin calls `main` as a constructor when loading a shared library; guarded with `if len(os.args) == 0 { return }`
- [x] **`source` field**: Added `source: string` to OLS `Diagnostic` struct; plugin diagnostics show `source=odin-lint` in editor
- [x] **Editor integration**: verified diagnostics appear in VS Code with squiggles + hover explanation
- [x] **LSP integration test**: automated test script (`/tmp/lsp_verify.py`) confirms C001+C003 fire correctly

#### Deferred to later milestones

- [ ] **Wider squiggle range**: currently col..col+1; should span the full identifier (polish)
- [ ] **Code actions (M5.5)**: wire `on_code_actions` to the autofix layer (`generate_fixes`)
- [ ] **Suppression in plugin context**: ensure `// odin-lint:ignore=C001` is respected using in-memory lines

**Gate 5: ✅ PASSED**
- [x] Plugin builds without errors: `./scripts/build_plugin.sh`
- [x] Diagnostics appear in editor for C001–C011 rules on file open
- [x] `source=odin-lint` shown on all plugin diagnostics
- [x] LSP smoke test confirms correct rule codes and messages

---

### ✅ Milestone 5.5 — MCP Gateway — COMPLETE (April 18 2026)

Pure Odin MCP server exposing odin-lint analysis to Claude Code and other
MCP clients. No Node.js or external runtime — the MCP protocol (JSON-RPC 2.0
with Content-Length framing) is implemented from scratch in Odin.

#### Architecture

```
Claude Code / AI agent
    ↓ MCP stdio (JSON-RPC + Content-Length framing)
artifacts/odin-lint-mcp   (src/mcp/ — package mcp_server)
    ├── imports vendor/odin-mcp/  — reusable protocol library
    └── imports src/core/         — lint rules, tree-sitter parser
```

#### Two-package design

**`vendor/odin-mcp/`** — standalone, reusable MCP protocol library.
No dependency on odin-lint. Any Odin project can import this to build
an MCP server without implementing the protocol from scratch.

Files:
- `types.odin` — `MCPServer`, `RegisteredTool`, `ToolDefinition`, `ToolHandler`, `RPCID`, `MCPRequest`
- `transport.odin` — `read_message` / `write_message` (Content-Length framing, identical to LSP)
- `json_helpers.odin` — `build_success_response`, `build_error_response`, `json_escape_string`
- `server.odin` — `server_init`, `server_register_tool`, `server_run` (dispatch loop)

Tool registration API:
```odin
ToolHandler :: proc(params: json.Value, allocator: mem.Allocator) -> (result: string, is_error: bool)

server_register_tool :: proc(s: ^MCPServer, tool: RegisteredTool)
server_run :: proc(s: ^MCPServer)  // blocks on stdin until EOF
```

**`src/mcp/`** — odin-lint specific server.

Files:
- `main.odin` — init tree-sitter parser, register tools, call `server_run`
- `tool_lint.odin` — Tier 1 tools (no OLS needed, call src/core directly)
- `tool_ols.odin` — Tier 2 stubs (full impl in M5.6)

#### Tools

| Tool | Tier | Implementation |
|------|------|----------------|
| `lint_file` | 1 — real | `analyze_file` from src/core |
| `lint_snippet` | 1 — real | `analyze_content` (new in-memory proc in src/core) |
| `lint_fix` | 1 — real | `analyze_file` + `generate_fixes` from src/core |
| `get_symbol` | 2 — stub | "not yet implemented — M5.6" |
| `export_symbols` | 2 — stub | "not yet implemented — M5.6" |

#### Memory model

- **Heap (process lifetime):** `MCPServer`, registered tools table, `TreeSitterASTParser`
- **Temp allocator (per request):** JSON bytes, parsed `json.Value` tree, response string
- `free_all(context.temp_allocator)` at end of each request loop iteration

#### `analyze_content` addition to src/core

`_plugin_run_rules` in `plugin_main.odin` is `@(private="file")`. A new
exported `analyze_content :: proc(file_path, content string, ts: ^TreeSitterASTParser, diags: ^[dynamic]Diagnostic)`
mirrors it — allows `lint_snippet` to run all rules on in-memory source
without going through disk. Also removes the duplication between
`plugin_main.odin` and the new MCP tool.

#### MCP protocol handled

- `initialize` → ServerInfo + `{"tools":{}}` capabilities
- `initialized` → notification, no response
- `tools/list` → array of ToolDefinition with JSON Schema
- `tools/call` → dispatch to handler, return `{content:[{type:"text",text:"..."}]}`
- `ping` → `{}`

#### Build

```bash
./scripts/build_mcp.sh   →   artifacts/odin-lint-mcp
```

Same tree-sitter linker flags as `build.sh` (src/mcp imports src/core which uses FFI).

#### Claude Code registration (`~/.claude/mcp_servers.json` or project `.mcp.json`):
```json
{
  "mcpServers": {
    "odin-lint": {
      "command": "/path/to/artifacts/odin-lint-mcp",
      "args": []
    }
  }
}
```

**Gate 5.5:** ✅ PASSED (April 18 2026)
- [x] `./scripts/build_mcp.sh` exits 0
- [x] `initialize` + `tools/list` respond correctly (5 tools listed)
- [x] `lint_file` returns real C001 diagnostics for `tests/C001_COR_MEMORY/c001_basic.odin`
- [x] `lint_snippet` returns diagnostics for in-memory source with violations
- [x] `lint_fix` returns proposed fix edits as JSON
- [x] `./scripts/test_our_codebase.sh` still passes (no regressions)
- [x] `vendor/odin-mcp` has no imports from `src/core` (verified by grep)

---

### 🔧 Milestone 5.6 — DNA Impact Analysis + Code Graph

*Prerequisite: Gate 5.5 — PASSED*

This milestone builds the Odin code graph: a native, SQLite-backed semantic
index that gives AI agents and future lint rules instant structural access to
the codebase without scanning files. It is the Odin-native answer to
CodeGraph (github.com/colbymchenry/codegraph), which has no Odin support,
runs on Node.js (reliability issues in practice), and has no memory ownership
semantics. Our differentiators: native binary, Odin-specific memory roles,
lint violations on nodes, and cross-FFI awareness.

#### Architecture decisions (April 18 2026)

**Decision 1 — SQLite is required, not optional.**
CodeGraph's entire MCP tool surface runs on SQL queries. Without it, graph
tools degrade to in-memory JSON lookups. We write SQLite C FFI bindings
(`src/db/sqlite_bindings.odin`) using the same pattern as tree-sitter — native
`.a` static library, no WASM, no Node. Stored in `.codegraph/odin_lint_graph.db`.

**Decision 2 — `nodes` + `edges` schema, not 4 separate tables.**
CodeGraph's `nodes`/`edges` model with kind discriminators is more general and
maintainable than our originally planned `functions`/`calls`/`variables`/`usages`
split. We extend it with Odin-specific columns that CodeGraph lacks entirely.

**Decision 3 — Track `references` edges, not just `calls`.**
To enable unused symbol detection (C013+) in M6, every edge kind must be
captured: calls, type references, constant/variable references, imports. A
symbol with zero incoming `references` edges and `is_exported = false` is dead
code. Getting this right now makes C013+ free queries later.

**Decision 4 — Two-pass extraction.**
Pass 1: index all symbol declarations (proc, type, constant, variable) into
`nodes`. Pass 2: resolve all call sites and references against the node index,
writing `edges`. Unresolved references (cross-package, foreign imports) are
stored as `unresolved_refs` for best-effort later resolution. Odin's explicit
`import` declarations make cross-package resolution more reliable than JS/TS.

**Decision 5 — `language` column future-proofs C interop.**
A `language TEXT DEFAULT 'odin'` column on `nodes` costs nothing now and
enables C nodes (via tree-sitter-c grammar) in a future milestone. The FFI
boundary is captured as `ffi_call` edges. C parsing deferred to M7+.

**Decision 6 — On-demand export, no file watcher.**
CodeGraph uses filesystem watching (FSEvents/inotify). For M5.6, `--export-symbols`
on-demand rebuild is sufficient. File watching is a later quality-of-life feature.
Note: CodeGraph also does not use git hooks despite earlier speculation — filesystem
watching is their approach, and on-demand beats both for an analysis tool.

**Decision 7 — LSP Call Hierarchy deferred to M6.**
The MCP tools (`get_dna_context`, `get_impact_radius`) fully cover the AI agent
use case. LSP call hierarchy is editor polish on the same data. Deferring keeps
M5.6 focused and avoids another OLS fork change cycle.

**Decision 8 — `run_lint_denoise` is a distinct tool, not an alias.**
CodeGraph has no equivalent. This is the lint-grounded fix loop: structured JSON
violations optimised for AI consumption (includes fix hints, source ranges).
It is our primary differentiator over CodeGraph and worth the dedicated tool slot.

---

#### SQLite Schema (`src/db/`)

```sql
-- nodes: every named symbol in the codebase
CREATE TABLE nodes (
    id            INTEGER PRIMARY KEY,
    name          TEXT NOT NULL,
    qualified_name TEXT,             -- "package.name" for cross-package resolution
    kind          TEXT NOT NULL,     -- "proc" | "type" | "constant" | "variable" | "import"
    language      TEXT DEFAULT 'odin', -- future: "c" for cross-FFI nodes
    file          TEXT NOT NULL,
    line          INTEGER,
    signature     TEXT,              -- proc signature string
    is_exported   INTEGER DEFAULT 0, -- 1 if accessible outside package
    memory_role   TEXT,              -- "allocator"|"deallocator"|"borrower"|"neutral"
    lint_violations TEXT             -- JSON array of rule IDs that fired on this node
);

-- edges: all relationships between nodes
CREATE TABLE edges (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER NOT NULL REFERENCES nodes(id),
    target_id   INTEGER NOT NULL REFERENCES nodes(id),
    kind        TEXT NOT NULL,  -- "calls"|"references"|"imports"|"returns"|"ffi_call"
    line        INTEGER         -- line in source where the edge originates
);

-- files: indexed source files with content hash for incremental re-index
CREATE TABLE files (
    path         TEXT PRIMARY KEY,
    content_hash TEXT NOT NULL,
    indexed_at   INTEGER         -- unix timestamp
);

-- unresolved_refs: call sites / references that couldn't be matched to a node in pass 2
CREATE TABLE unresolved_refs (
    id          INTEGER PRIMARY KEY,
    source_id   INTEGER REFERENCES nodes(id),
    target_name TEXT NOT NULL,
    kind        TEXT NOT NULL,
    file        TEXT,
    line        INTEGER
);

-- FTS5 for fast symbol search (codegraph_search equivalent)
CREATE VIRTUAL TABLE nodes_fts USING fts5(name, qualified_name, content='nodes', content_rowid='id');
```

Key queries enabled:

```sql
-- Impact radius: everything that calls proc X (direct)
SELECT n.name, n.file, n.line FROM nodes n
JOIN edges e ON e.source_id = n.id
WHERE e.target_id = ? AND e.kind = 'calls';

-- Dead code candidates: non-exported symbols with no incoming references
SELECT name, kind, file, line FROM nodes
WHERE is_exported = 0
AND id NOT IN (SELECT target_id FROM edges WHERE kind IN ('calls','references'));

-- All allocators
SELECT name, file, line FROM nodes
WHERE memory_role = 'allocator';
```

#### `dna_exporter.odin` — extraction pipeline

```
src/core/dna_exporter.odin
  export_symbols(paths []string, db_path string)
    Pass 1 — index_declarations():
      For each .odin file: run SCM query for proc/type/constant/variable declarations
      INSERT INTO nodes; INSERT INTO files with content hash
    Pass 2 — resolve_references():
      For each .odin file: run SCM query for call_expression + selector_expression
      Match callee name against nodes table (qualified_name first, name fallback)
      INSERT INTO edges (kind='calls'|'references'|'imports')
      Unmatched → INSERT INTO unresolved_refs
    Pass 3 — tag_memory_roles():
      For each proc node: inspect its outgoing 'calls' edges
      Heuristic: calls make/new + returns pointer/slice → "allocator"
      Heuristic: calls free/delete on parameter → "deallocator"
      C012 _owned suffix on return var → "allocator" (if present)
      Otherwise "borrower" or "neutral"
    Pass 4 — attach_lint_violations():
      Run analyze_content on each file; map violation line→node
      UPDATE nodes SET lint_violations = '["C001"]' where matched
    Pass 5 — write_symbols_json():
      Export nodes + edges as symbols.json (portable AI format)
      Rebuild FTS5 index
```

SCM queries needed (new files in `ffi/tree_sitter/queries/`):
- `declarations.scm` — captures proc/type/constant/variable declarations
- `references.scm` — captures call_expression, selector_expression, import_declaration

#### MCP tool surface for M5.6

| Tool | Status | Notes |
|------|--------|-------|
| `get_dna_context(proc_name)` | New | callers + callees + memory_role + lint_violations |
| `get_impact_radius(proc_name, depth?)` | New | transitive callers up to depth (default 3) |
| `find_allocators()` | New | all nodes with memory_role = "allocator" |
| `find_all_references(symbol)` | New | all edges targeting symbol — foundation for rename |
| `run_lint_denoise(source)` | New | lint_snippet output optimised for AI fix loop |
| `get_symbol(file, symbol)` | Promote stub | query nodes table by name + file |
| `export_symbols(path?)` | Promote stub | trigger export_symbols pipeline, return db path |

`run_lint_denoise` differs from `lint_snippet` in output shape: it returns
structured fix objects (rule_id, line, col, fix_text, source_range) rather than
the flat diagnostic array, making it directly consumable by an AI fix agent.

`find_all_references` is the prerequisite for `rename_symbol` (M6). Exposing it
now as a standalone MCP tool lets it be validated before refactoring is built on top.

#### Future milestones prepared by M5.6

| Feature | Milestone | How M5.6 enables it |
|---------|-----------|---------------------|
| Unused symbol rules (C013+) | M6 | `references` edges + `is_exported` → SQL query |
| Rename refactoring | M6 | `find_all_references` → bulk FixEdits |
| LSP Call Hierarchy | M6 | same SQLite graph, new OLS hooks |
| C cross-FFI call graph | M7+ | `language` column already in schema |
| Vector embeddings (`--embed`) | M7+ | `node_vectors` table already planned in schema |

**Gate 5.6:**
- [ ] SQLite C FFI bindings compile and link (`src/db/sqlite_bindings.odin`)
- [ ] `nodes` + `edges` + `files` + `unresolved_refs` schema created in `.codegraph/odin_lint_graph.db`
- [ ] FTS5 virtual table built and synced on export
- [ ] `--export-symbols` CLI flag runs all 5 passes; exits 0 on our codebase
- [ ] `symbols.json` produced alongside the SQLite db
- [ ] Memory roles tagged for all proc nodes in our codebase
- [ ] Lint violations attached to nodes where C001–C011 fire
- [ ] `get_dna_context` returns callers + callees + memory_role
- [ ] `get_impact_radius` returns correct transitive callers (depth=2 verified by hand)
- [ ] `find_allocators` returns only nodes with memory_role="allocator"
- [ ] `find_all_references` returns all edge targets for a named symbol
- [ ] `run_lint_denoise` returns structured fix objects (not just diagnostic array)
- [ ] `get_symbol` stub promoted — queries nodes table, returns signature + location
- [ ] `export_symbols` stub promoted — triggers pipeline, returns db path
- [ ] Dead code query demonstrated: non-exported proc with 0 incoming references found
- [ ] `./scripts/test_our_codebase.sh` still passes (no regressions)

---

### ✅ Milestone 6 — Extended Rules + Refactoring Foundation — COMPLETE (April 21 2026)

*Prerequisite: Gate 5.6 (code graph + SQLite working)*
*Full C012 M6 spec: `plans/C012-SEMANTIC-NAMING-TODO.md` → M6 Implementation Detail*

M6 has four categories of work:

1. **Scope-aware naming rules** (C016–C018) — pure tree-sitter, no type inference needed
2. **Dead code rules** (C013–C015) — graph queries over `nodes`/`edges`
3. **Type-gated correctness rules** (C012 Phase 2, C101, C201, C202) — require OLS type resolution
4. **Refactoring foundation** — rename + LSP Call Hierarchy, built on `find_all_references`

> **C019 (type marker suffixes) is planned after C012 Phase 2** — it needs type
> inference to catch inferred `:=` declarations, not just explicit type annotations.
> **⚠️ Conventions for C019 must be discussed with the user before implementation.**

All C012 Phase 2 rules live on the **OLS plugin path** (`src/rules/correctness/`),
not the tree-sitter CLI path. They use `^ast.File` + OLS type resolution.
The implementation file is `src/rules/correctness/c012-OLS-Naming.odin` (new).

---

#### C016–C018: Scope-Aware Naming Rules (tree-sitter tier)

Extends C003/C007 with scope and visibility awareness. All optional, configurable
via `odin-lint.toml`. All fire `warn` tier.

**M6 implementation order:**
1. ✅ Grammar exploration complete (April 20 2026) — see findings below
2. C016 — local variable naming
3. C017 — package-level variable naming
4. C018 — proc visibility naming split
5. Wire all three into `odin-lint.toml` with configurable patterns

| Rule | Scope | Convention | Check |
|------|-------|-----------|-------|
| C016 | local variable (inside proc body) | `snake_case` | all lowercase + underscores, no uppercase |
| C017 | package-level variable | `camelCase` | starts lowercase, contains at least one uppercase OR is single word |
| C018 | proc with `@(private)` / `@(private="file")` | `snake_case` | starts lowercase, no uppercase run at start |
| C018 | proc without `@(private)` (API surface) | `PascalCase` | starts uppercase |

**Notes:**
- C016/C017 only apply to explicitly typed declarations — `:=` inferred vars are
  out of scope for tree-sitter (no type info). Inferred var naming deferred to C019.
- C018 replaces/supersedes C003 for projects that adopt the visibility convention.
  C003 remains active by default; C018 is opt-in.
- `allowed_acronyms` list in toml (e.g. `["HTTP","URL","JSON"]`) exempts names
  that are all-uppercase acronyms from the PascalCase check.

##### Grammar Exploration Findings (April 20 2026)

**C016 — Local variable node types**
- Package-level `:=` → `variable_declaration` (different node — no cross-contamination)
- Inside-proc `:=` AND `=` reassignment → both `assignment_statement`
- `assignment_statement` children: `attributes`, `expression` (LHS name), anonymous operator token, `expression`/`procedure` (RHS)
- SCM pattern: `(assignment_statement (identifier) @local_var)`
- **Odin filter required**: check source line text for `:=` after identifier end to skip `=` reassignments (no predicate support in our query engine)

**C017 — Package-level variable node types**
- `var x: Type = value` → `var_declaration` (children: `attributes`, `expression`, `type`)
- `x := value` at package level → `variable_declaration` (children: `attributes`, `expression`, `procedure`)
- Both live under `source_file > declaration` — naturally scoped, no proc-body contamination
- SCM: two patterns needed, one for each form

**C018 — `@(private)` attribute structure**
- `@(private)` → `procedure_declaration > attributes > attribute > identifier("private")`
- `@(private="file")` → same path, attribute also has a `string` child
- SCM: `(procedure_declaration (identifier) @proc_name)` captures all procs (with or without attributes)
- **Odin logic**: walk `ts_node_parent` of `proc_name` → scan children for `attributes` node → scan its children for `attribute` → check if any `identifier` child text == `"private"` using `ts_node_child_count` + `ts_node_child` + `ts_node_type` (all bindings confirmed present)
- No SCM predicates needed — all attribute checking done in Odin

**Shared helper to write**: `_is_declaration(node TSNode, line string) -> bool` — checks if `:=` follows the identifier in the source line (distinguishes new declarations from reassignments in `assignment_statement`).

**Gate C016–C018:**
- [x] Grammar exploration complete — node types documented
- [ ] C016 fires on uppercase local variable, silent on snake_case
- [ ] C017 fires on snake_case package-level variable, silent on camelCase
- [ ] C018 fires on `@(private)` proc with PascalCase name
- [ ] C018 fires on public proc with snake_case name (opt-in, off by default)
- [ ] All three configurable via `odin-lint.toml` patterns
- [ ] 3 pass + 3 fail fixtures for each rule
- [ ] Clean on our own codebase

---

#### C019: Type Marker Suffixes (post-C012, requires type inference)

> **⚠️ Conventions must be discussed with the user before implementation.**
> Do not implement C019 until suffix conventions are agreed and documented here.

Enforces suffix conventions on variables based on their type. Requires C012 Phase 2
type infrastructure to catch inferred `:=` declarations.

Planned suffix table (to be finalised with user):

| Type | Suggested suffix | Example |
|------|-----------------|---------|
| pointer (`^T`) | `_ptr` | `player_ptr` |
| dynamic array (`[dynamic]T`) | `_arr` or `s` suffix | `players_arr` |
| map (`map[K]V`) | `_map` or `_by_key` | `name_map`, `player_by_id` |
| slice (`[]T`) | `_slice` or `s` suffix | `players_slice` |
| maybe/optional | `_opt` | `player_opt` |

---

#### C013+: Dead Code Rules (graph-query tier)

These rules are free queries over the M5.6 graph. No new AST analysis needed.

| Rule | Fires when | Query |
|------|-----------|-------|
| C013 | Import declared but never referenced | `imports` edge from file with no outgoing `references` edges using that package |
| C014 | Proc declared, not exported, zero callers | `is_exported=0` + no incoming `calls` edges |
| C015 | Constant/variable declared, never referenced | `is_exported=0` + no incoming `references` edges |

All fire INFO tier. All configurable via `[domains] dead_code = true` in `odin-lint.toml`.

These are the "import not used" / "symbol never used" diagnostics the Java
Language Server provides. With the code graph built in M5.6, implementing them
is a matter of writing the lint rule handlers that issue SQL queries — no new
tree-sitter work required.

---

#### Refactoring Foundation

**`rename_symbol` MCP tool** — built directly on `find_all_references` (M5.6):
1. Query all incoming `calls` + `references` edges for the target node
2. Generate a `FixEdit` per location (file, line, col, old_name → new_name)
3. Return the edit set; client applies via `workspace/applyEdit` or `--fix`

Safe rename: does not touch string literals, comments, or doc strings.
Unsafe rename (`--unsafe-fix`): includes string literals (e.g. reflection-based code).

**LSP Call Hierarchy** — deferred from M5.6:
- Add `CallHierarchy` capability to OLS plugin interface
- Wire `textDocument/prepareCallHierarchy`, `callHierarchy/incomingCalls`,
  `callHierarchy/outgoingCalls` in `requests.odin`
- Implement in `plugin_main.odin`: query SQLite graph for callers/callees
- VS Code "Show Call Hierarchy" works on any Odin proc

---

#### C012 Phase 2 — Type-Gated Ownership Naming

*Full spec in `plans/C012-SEMANTIC-NAMING-TODO.md`. Summary:*

| Sub-rule | Fires when | Requires |
|----------|-----------|----------|
| C012-T1 | `mem.Allocator`-typed var has no `alloc`/`allocator` in name | OLS type resolution |
| C012-T2 | `mem.Arena`/`virtual.Arena`-typed var has no `arena` in name | OLS type resolution |
| C012-T3 | Return of allocator-role proc not named `_owned` | OLS + DNA export |
| C012-S4 | Arena type declarations (promoted from M3.3 heuristic) | OLS type resolution |

All fire INFO tier. All require `--enable-c012`. All silent by default.

The `dna_exporter.odin` `infer_memory_role_from_name` proc is updated in M6
to use `_owned` return variable names as the primary signal for
`"memory_role": "allocator"` — making C012 adoption directly improve the
quality of the AI export layer.

**Gate C012-T (part of Gate 6):**
- [ ] C012-T1 fires on `mem.Allocator`-typed variable with opaque name
- [ ] C012-T2 fires on `mem.Arena`-typed variable without `arena` in name
- [ ] C012-T3 fires when callee has `memory_role == "allocator"` and LHS has no `_owned`
- [ ] All T sub-rules silent when C012 disabled (default)
- [ ] `symbols.json` `memory_role` populated for 100% of procedures
- [ ] 3 pass + 3 fail fixtures for each T sub-rule
- [ ] False positive rate on RuiShin < 5%

---

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
- [x] C016–C018 grammar exploration complete
- [x] C016 fires on uppercase local variable name
- [x] C017 fires on snake_case package-level variable name
- [x] C018 fires on visibility/naming mismatch (opt-in)
- [x] C016–C018 patterns configurable via `odin-lint.toml`
- [ ] C013 fires on unused imports — SKIPPED (Odin compiler catches this; no value added)
- [x] C014 fires on non-exported proc with zero callers
- [x] C015 fires on non-exported constant/variable with zero references
- [x] `dead_code` domain in `odin-lint.toml` enables/suppresses C014–C015
- [ ] C012-T1, T2, T3 implemented and tested → moved to M7.1 (BLOCKED until M7 memory_role)
- [ ] `dna_exporter.odin` populates `memory_role` for all procedures → moved to M7 Tier 4
- [ ] C101 false positive rate < 5% on RuiShin → moved to M7.1
- [ ] C201 fires on unchecked error returns, silent on intentional ignores → moved to M7.1
- [ ] C202 fires on incomplete enum switches → moved to M7.1
- [ ] `rename_symbol` MCP tool generates correct FixEdit set for a proc rename → moved to M7.1
- [ ] Rename does not touch string literals (safe mode) → moved to M7.1
- [ ] C019 conventions agreed with user — deferred to post-C012 Phase 2 (M7.1+); requires type inference for := vars
- [ ] LSP Call Hierarchy: VS Code "Show Call Hierarchy" works on an Odin proc → moved to M7.1
- [ ] All new rules: 3 pass + 3 fail fixtures

---

### ✅ Milestone 6.5 — Structural Rules (B-category) — COMPLETE (April 21 2026)

**New rule category.** "B" rules operate on the raw token stream, not the AST.
They fire when the file is too broken for the AST to be trusted.

---

#### B001: Unmatched Brace / Unclosed Block

**Category:** Structural  
**Severity:** Error  
**Opt-in:** No — B001 runs by default on every file

##### What it detects

A `{` that is opened inside a procedure, struct, enum, union, or control-flow
block but never closed before the end of the file, or a `}` encountered when no
matching `{` is on the stack (surplus brace). The canonical symptom is that the
Odin compiler reports "undeclared name" errors in _other files_ or at _distant_
locations with no indication of where the structural imbalance actually is — the
compiler desyncs silently on brace imbalance.

##### Why this matters

The Odin compiler does not pinpoint the mismatched brace. It reports downstream
consequences instead — type errors, undeclared identifiers, sometimes in entirely
unrelated files. B001 surfaces the actual fault location immediately, saving
potentially hours of debugging.

##### Diagnostic messages

```
B001 [structural]: unclosed block opened at line N, col M — expected matching '}'
B001 [structural]: unexpected '}' at line N, col M — no matching opening '{'
```

##### Implementation

**Token-level scan, not AST.** When a file has an unmatched brace tree-sitter
produces error nodes and the AST shape is unreliable. Do not trust `ts_node_is_error`
alone — the AST may be partially constructed with wrong structure. Prefer a
linear scan of the raw file bytes:

1. Read the file as bytes (already available from `analyze_content`).
2. Walk byte-by-byte, tracking:
   - Inside a single-line comment (`//` until `\n`) — skip `{` / `}`.
   - Inside a block comment (`/*` until `*/`, nestable in Odin) — skip `{` / `}`.
   - Inside a string literal (`"..."` — `\"` escapes, no raw strings in Odin) — skip.
   - Inside a rune literal (`'...'`) — skip.
3. On every `{`: push `(line, col)` onto a stack.
4. On every `}`: if stack is non-empty, pop; else emit surplus-brace diagnostic.
5. At end of file: any remaining stack entries are unclosed-block diagnostics.

**Odin-specific note:** Odin allows nested block comments (`/* /* */ */`). Track
comment nesting depth with a counter, not a boolean flag.

**Integration:** Run B001 first, before tree-sitter parsing. If B001 fires, skip
all other rules for that file (the AST is untrustworthy). Emit a note alongside
each B001 violation: `"other diagnostics suppressed for this file"`.

**File:** `src/core/b001-STR-BraceBalance.odin`  
**SCM query:** None — pure byte scan.

##### Gate 6.5

- [x] B001 fires on unclosed `{` at correct line and column
- [x] B001 fires on surplus `}` at correct line and column
- [x] B001 silent on perfectly balanced files
- [x] String literals, rune literals, and comments correctly excluded
- [x] Nested block comments (`/* /* */ */`) handled correctly
- [x] When B001 fires, remaining rules are suppressed for that file with note
- [x] 3 pass + 3 fail fixtures (unclosed, surplus, balanced)
- [x] Own codebase: 0 B001 violations
- [x] RuiShin corpus: 1 file with real brace imbalance detected (`tools/odin/final_debug.odin`), src/ clean

---

### ⬜ Milestone 6.6 — C001 False Positive Reduction (AST Layer)

*Prerequisite: Gate 6.5 (B001 complete) — PASSED*  
*Unlocks: M7 Graph-Semantic Layer (same escape-hatch framework extended)*

**Context.** RuiShin `src/` scan (109 files, April 2026) produced 72 C001 hits.
Manual review classified 62 as false positives in three patterns and identified
3 confirmed bugs in the existing escape-hatch logic. This milestone fixes those
bugs and adds a new heuristic escape hatch, targeting ≤ 10 false positives on
the same corpus.

The improvements are purely within `src/core/c001-COR-Memory.odin` — no schema
changes, no graph queries. M7 (graph layer) extends the same escape-hatch
framework with richer signal once the AST layer is clean.

---

#### Bug 1 — `has_allocator_arg` patterns are too narrow

**Root cause.** The function tests three narrow text patterns against the make()
line. `runtime.default_allocator()` fails all three:

| Pattern | Why it misses `default_allocator()` |
|---------|-------------------------------------|
| `"temp_allocator"` | literal substring match, not present |
| `".allocator"` | `.` separates the package, not a field — `runtime.default_allocator` contains no `.allocator` substring |
| `"allocator)"` | the `)` closes `default_allocator()`'s own argument list; `allocator)` is never contiguous |

Same failure for `mem.arena_allocator(&x)` and any named allocator variable
like `path_scratch` or `frame_scratch`.

**Fix.** Replace the three-pattern check with a single broad match:

```odin
return strings.contains(args, "allocator")
```

If the word `allocator` appears anywhere in the argument list, the call is using
a custom or explicit allocator. This catches `runtime.default_allocator()`,
`mem.arena_allocator(...)`, `context.temp_allocator`, `context.allocator`, and
any proc that ends in `_allocator`. It still misses opaque variables like
`path_scratch` — those are handled in M7 (Tier 4 `memory_role` propagation).

**Impact.** Eliminates roughly 30 of the 62 false positives (Category A: explicit
arena/scratch allocators).

---

#### Bug 2 — `changes_context_allocator` block walk mismatch

**Root cause.** Confirmed via live test: a proc that starts with
`context.allocator = context.temp_allocator` still triggers C001 on subsequent
`make()` calls. The `has_arena` flag is set but the assignment's AST node
structure does not match what `changes_context_allocator` expects. Likely the
`assignment_statement` is wrapped in an extra expression node in the actual
tree-sitter Odin grammar.

**Fix.** Debug by printing the node type path for a known failing case. Adjust
`changes_context_allocator` to match the actual tree structure. Add a targeted
test fixture:

```odin
// c001_fixture_temp_alloc.odin — must produce 0 C001 violations
test_temp :: proc() {
    context.allocator = context.temp_allocator
    buf := make([dynamic]u8, 0, 128)
    _ = buf
}
```

**Impact.** Eliminates roughly 8 false positives (Category C: temp-allocator
procs in `bidi.odin`, `text/layout.odin`, `text/shaper.odin`).

---

#### Bug 3 — Multi-line `make()` allocator argument not scanned

**Root cause.** `uses_non_default_allocator` reads only `file_lines[call_node.start_line - 1]`.
Multi-line calls with the allocator argument on a continuation line are invisible:

```odin
buf := make(          // start_line → only this line is read
    [dynamic]u8,
    0, 128,
    runtime.default_allocator(),  // never seen
)
```

**Fix.** Scan from `call_node.start_line` to `call_node.end_line`, joining the
lines before searching for the `"allocator"` substring. Guard against very long
ranges (cap at 20 lines to avoid pathological cases).

**Impact.** Eliminates roughly 4 false positives (multi-line init patterns).

---

#### Tier 2 — `_init` proc name heuristic

**Pattern.** Procs named `*_init`, `init_*`, or exactly `init` are by
convention lifetime-scoped initializers. Their allocations live for the program
or subsystem lifetime and are intentionally never `defer`-freed individually.
This is idiomatic Odin (and C, and Go): an `init` proc sets up module state
once; a matching `destroy` or `shutdown` proc tears it down.

**Fix.** In `analyze_block`, detect the enclosing proc name (already available
from the AST walk context). If the proc name matches `*_init`, `init_*`, or
`init`, set `ctx.has_arena = true` to suppress C001 for the entire block.

```odin
// In the block analysis loop setup:
if strings.has_suffix(proc_name, "_init") ||
   strings.has_prefix(proc_name, "init_") ||
   proc_name == "init" {
    ctx.has_arena = true
}
```

This is a heuristic, not a guarantee. A genuine leak inside an `_init` proc
(e.g. a loop body that allocates per-iteration) would be suppressed. Accept
this trade-off: the naming convention is strong enough that false negatives in
`_init` procs are rare and the user can add a suppression comment for the
exceptional case.

**Impact.** Eliminates roughly 16 false positives (Category B: init-and-hold).

---

#### Gate 6.6

- [ ] `has_allocator_arg` matches `runtime.default_allocator()` — add to existing fixture
- [ ] `has_allocator_arg` matches `mem.arena_allocator(&x)` — add to existing fixture
- [ ] `context.allocator = context.temp_allocator` at proc top suppresses all C001 in that proc
- [ ] Multi-line `make()` with allocator on continuation line: no C001 violation
- [ ] `_init` / `init_*` proc heuristic suppresses all C001 in initializer procs
- [ ] 5 new pass fixtures (one per fixed case)
- [ ] Existing 3 fail fixtures still fire
- [ ] RuiShin `src/` false positive count: ≤ 10 (down from 62)
- [ ] Own codebase: 0 regressions
- [ ] Remaining ~10 FPs documented in `plans/ruishin_check_c001.md` as known architectural gap → deferred to M7

---

### ✅ Milestone 6.9 — Package-Scope Linting Foundation — COMPLETE (April 21 2026)

*Prerequisite: Gate 6.6 complete*  
*Introduces: B002, B003 — first rules that require multi-file context*  
*Establishes: canonical four-scope model (see Section 14)*

**Context.** odin-lint has always operated file-by-file, but Odin's compilation
model is package-based: every `.odin` file in a directory that shares the same
`package foo` declaration belongs to the same namespace. File boundaries are
purely organisational. A variable declared in `graphics_a.odin` is visible in
`graphics_b.odin` without any import — they are the same package.

This means several existing rules produce false positives (C001, C014/C015) or
incomplete results (C017) because they cannot see across file boundaries within
a package. M6.9 establishes the architecture that fixes this, and delivers two
immediately useful structural rules as its first payoff.

Odin's package model (confirmed):
- All `.odin` files in a directory sharing the same `package` declaration form one package.
- Subfolders are always separate packages — Odin does not recurse.
- Having two different package names in the same directory (excluding `_test`
  variants) is a **compiler error** that odin-lint can catch before the build.

---

#### The Four Analysis Scopes (see Section 14 for full definition)

| Scope | Unit | Examples |
|-------|------|---------|
| **File** | Single `.odin` file | C001, C002, B001 |
| **Package** | All files in a dir with matching `package` decl | B002, B003, C017 |
| **Project** | All packages in the project | DNA graph, C014/C015, rename |
| **External/FFI** | Vendor + C libraries | C011, excluded from most rules |

Rules must be clearly tagged with their required scope. A file-scope rule that
accidentally depends on cross-file information is architecturally wrong — the
fix is either to move it to package scope or accept it as a known limitation.

---

#### B002 — Package Name Consistency

**Pattern.** A file in a directory declares a `package` name that differs from
the majority of other files in the same directory.

**Why it matters.** Odin refuses to compile a package where files disagree on
the package name. This is a build error that manifests confusingly. Catching it
at lint time gives a clear, actionable message.

**Algorithm:**
1. Collect `package <name>` declarations from all `.odin` files in the directory.
2. Exclude `_test` variant: `package foo_test` is always valid alongside `package foo`.
3. Determine majority name (most common, or first if tied).
4. Flag every file whose declaration differs from the majority.

**Severity:** ERROR (will fail the build).

**Example:**
```
src/graphics/shader.odin:1: B002 [structural] package "shader" — expected "graphics" (11/12 files)
```

---

#### B003 — Subfolder Shares Parent Package Name

**Pattern.** A subfolder contains `.odin` files with the same `package` name as
its parent directory.

**Why it matters.** In Odin subfolders are always separate packages. If
`src/graphics/` uses `package graphics` and `src/graphics/utils/` also uses
`package graphics`, the two are NOT the same package — the compiler treats them
as separate and the utils package must be explicitly imported. This is almost
always an organisational mistake (the developer expected the files to be part of
the same package without realising subfolders are separate).

**Algorithm:**
1. For each directory being linted, record its package name.
2. For each subdirectory, record its package name.
3. If a subdirectory's package name matches the parent's package name → warn.

**Severity:** WARNING (compiles, but almost certainly wrong intent).

**Example:**
```
src/graphics/utils/math_helpers.odin:1: B003 [structural] package "graphics" — subfolder
  is a separate package from parent src/graphics/; did you mean package "graphics_utils"?
```

---

#### Architecture change: package-grouped scanning

The CLI scan loop changes from:

```
for each file → analyze_file(file)
```

to:

```
for each directory → collect files → group by package_name → analyze_package(pkg)
  for each file in pkg → analyze_file(file, pkg_context)
```

`PackageContext` carries:
- `name: string` — the agreed package name
- `files: []string` — all files in the package
- `top_level_symbols: map[string]SymbolKind` — populated lazily on first use

Rules that need only file context receive `pkg_context = nil` (unchanged path).
Rules that need package context (B002, B003, C017) query `pkg_context`.

---

#### Gate 6.9

- [ ] CLI scan groups files by directory + matching package declaration
- [ ] `PackageContext` struct defined and populated before per-file analysis
- [ ] B002 fires on file with wrong package declaration; silent on correct files
- [ ] B002 silent on `_test` package variants
- [ ] B003 fires when subfolder shares parent package name
- [ ] B003 silent when subfolder has distinct package name
- [ ] 3 pass + 3 fail fixtures for B002; 2 pass + 2 fail for B003
- [ ] Own codebase: 0 regressions
- [ ] RuiShin src/: B002 and B003 report zero (codebase is clean)

---

### ✅ Milestone 7 — Graph Enrichment for LLM Tooling + Refactoring — COMPLETE (April 21 2026)

*Prerequisite: Gate 6.9 (package-scope foundation) + Gate 5.6 (graph DB)*  
*Reframed from original "C001 FP via graph" — see architecture rationale below*  
*Unlocks: richer MCP context, C012-T, rename_symbol foundation*

**Architecture rationale (April 2026).** Investigation into the remaining C001
false positives in RuiShin revealed a deeper truth: the root causes (`path_scratch
:= g2d_get_path_scratch()` returning `mem.Allocator`) require **return-type
tracking** — knowing what a proc returns, not just what it calls. This is firmly
LSP-layer territory, not file-scope linting.

The correct architecture:

| Layer | Scope | Owns |
|-------|-------|------|
| **odin-lint** | File / Package | Syntactic + local semantic rules (C001–C020, B001–B003) |
| **DNA graph** | Project | Cross-package call graph, memory roles, symbol index |
| **OLS / LSP** | Project + types | Full type resolution, hover, go-to-def |

C001 FPs that require cross-file or return-type information are **accepted as
known limitations of file-scope analysis**. The graph layer is not a workaround
for linter limitations — it is a first-class service for LLM tooling and
refactoring. These are separate concerns and must remain separate.

---

#### M7 Goals

**1. Proper variable indexing**
- Restrict `var_declaration` capture in `declarations.scm` to top-level only
  (anchor to `source_file`), eliminating local variables from the `nodes` table.
- When inserting variable nodes, detect `: mem.Allocator` / `: runtime.Allocator`
  type annotations and set `memory_role='allocator'` immediately in Pass 1.

**2. Proc return-type tracking**
- Extend `nodes` schema with `return_type TEXT` column.
- Pass 1 extracts the return type string from proc signatures.
- Pass 3 uses `return_type` to tag procs that return `mem.Allocator` as
  `memory_role='allocator'` (e.g. `g2d_get_path_scratch`).
- This makes allocator-returning factory procs visible to MCP queries.

**3. Richer `get_dna_context` MCP output**
- Include variable nodes with `memory_role` in context responses.
- Include return type in proc node output.
- `find_allocators()` now returns both allocator-role procs AND allocator-typed variables.

**4. C012-T unlock**
- `memory_role='allocator'` on variables is the prerequisite for:
  - C012-T1: `mem.Allocator`-typed variable with opaque name → suggest `_alloc` suffix
  - C012-T3: callee has `memory_role='allocator'` and LHS has no `_owned`

**5. Incremental graph rebuild (file-hash cache)**

The current `--export-symbols` wipes and rebuilds the entire graph on every
run. For large projects this is slow. M7 makes it incremental:

1. **Eviction** — at export start, delete `nodes`/`edges`/`files` rows for
   paths that no longer exist on disk. Prevents stale entries from deleted files.
2. **Skip unchanged files** — for each file, compare its current content hash
   against the stored hash in the `files` table. If identical, skip re-parsing
   and re-indexing entirely (existing nodes/edges are still valid).
3. **Re-index changed files** — if the hash differs, delete all nodes and edges
   whose `file` column matches, then run Pass 1–4 for that file only.

This makes repeated `--export-symbols` runs (CI, watch mode, post-save hooks)
fast regardless of project size. The lint pass itself stays cache-free — file
I/O and tree-sitter parsing per file is fast enough that caching adds more
complexity than it saves.

The `files` table already has `hash TEXT` and `indexed_at INTEGER` columns —
no schema changes required.

---

#### Gate 7

- [ ] `declarations.scm` `var_declaration` capture anchored to `source_file` (no local vars)
- [ ] Pass 1 tags `: mem.Allocator` / `: runtime.Allocator` variables with `memory_role='allocator'`
- [ ] `nodes` schema extended with `return_type TEXT`
- [ ] Pass 1 extracts return type from proc signature strings
- [ ] Pass 3 tags procs returning `mem.Allocator` / `runtime.Allocator` as `memory_role='allocator'`
- [ ] `get_dna_context` MCP response includes variable roles and proc return types
- [ ] `find_allocators()` returns allocator-role procs AND allocator-typed variables
- [ ] C012-T gate criteria re-evaluated — T1 and T3 now achievable
- [ ] Incremental export: evict nodes/edges for deleted files on each export run
- [ ] Incremental export: unchanged files (same hash) are skipped — nodes/edges reused
- [ ] Incremental export: changed files are re-indexed (old nodes/edges deleted first)
- [ ] Verified: full rebuild and incremental rebuild produce identical graph content
- [ ] Own codebase: 0 regressions after graph rebuild
- [ ] RuiShin: `find_allocators()` correctly identifies `g2d_get_path_scratch`, `g2d_get_frame_scratch`

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

13. **Call graph intelligence architecturally belongs in the LSP, not in individual
    tools** — LSP 3.16 already defines `callHierarchy/incomingCalls` and
    `callHierarchy/outgoingCalls`. Every language server author knows their language
    best and already has the type-resolved AST. The right long-term solution is OLS
    implementing `callHierarchy` properly; the right short-term solution is the SQLite
    graph in M5.6. Build the SQLite layer now; plan to delegate to OLS once it's ready.
    The two can coexist indefinitely — SQLite for batch/AI export, OLS for live editor
    queries.

14. **Study reference implementations before designing storage schemas** — CodeGraph
    (github.com/colbymchenry/codegraph) uses the same tree-sitter + SQLite + MCP stack
    and has solved incremental sync and embedding storage cleanly. Its MIT license makes
    it freely referenceable. Always check what the ecosystem has already solved before
    designing from scratch.

### New for V7.3: Code Graph Architecture (April 18 2026)

20. **CodeGraph analysis confirmed `nodes`/`edges` over 4-table split** — CodeGraph
    (github.com/colbymchenry/codegraph) uses `nodes`/`edges` with kind discriminators
    (22 node kinds, 12 edge kinds). This is more general and maintainable than a fixed
    `functions`/`calls`/`variables`/`usages` schema. We extend it with Odin-specific
    columns (`memory_role`, `lint_violations`) that CodeGraph lacks entirely.

21. **Track `references` edges from day one** — if you only track `calls`, unused
    import/type/constant detection requires a full rescan later. Capturing all
    reference kinds at index time makes C013-C015 (dead code rules) free SQL queries
    in M6. Schema decisions made once; rules added incrementally.

22. **The C FFI boundary is naturally represented as `ffi_call` edges with a `language`
    column** — Odin's `foreign` declarations are explicit and tree-sitter-parseable.
    Adding `language TEXT DEFAULT 'odin'` now costs nothing and future-proofs for
    cross-FFI call graph analysis (M7+). C macros remain a known limitation of
    tree-sitter-c: macro-generated functions are invisible to the graph.

23. **`find_all_references` is the prerequisite for safe rename** — every refactoring
    operation that renames a symbol decomposes to: find all references + generate a
    FixEdit per location. Building this as a standalone MCP tool in M5.6 lets it be
    validated before `rename_symbol` is layered on top in M6.

24. **Dead code detection is a graph query, not a lint rule** — "unused import" and
    "symbol never used" diagnostics (C013-C015) are `SELECT` statements over the
    `nodes`/`edges` tables. They require no new tree-sitter patterns and no new rule
    infrastructure — just the graph from M5.6. Deferring them to M6 is the correct
    sequencing; they fall out naturally once the graph exists.

### From the April 2026 Ecosystem Survey

*Full research document: `plans/clippy-lessons.md`*

15. **Linter domains beat global config** — Biome v2's "linter domains" auto-enable
    rule groups based on project context (detected dependencies, directories, declared
    version). odin-lint adopts this as `[domains]` in `odin-lint.toml`: `ffi = true`
    enables C011 automatically; `odin_2026 = true` enables migration rules C009/C010.
    Auto-detect `ffi = true` when `ffi/` directory exists. This eliminates noise for
    projects that don't need specific rule groups.

16. **`--unsafe-fix` is a distinct tier from `--fix`** — Ruff distinguishes safe
    mechanical fixes (rename, insert defer) from fixes that change API surface
    (migration to a different API). C009 (`core:os/old` → `core:os`) is unsafe
    because the new os API has different calling conventions. Never apply API-surface
    changes silently.

17. **Quality over quantity is the Clippy lesson** — Clippy entered a 12-week feature
    freeze in mid-2025 because 750+ rules became unmaintainable. Every rule needs
    indefinite maintenance as the language evolves. Our ~12 high-quality, well-tested
    rules are healthier than racing to a large count.

18. **The type-awareness problem has one practical solution for us** — Every major
    ecosystem (Biome building its own type inference, Oxlint integrating typescript-go,
    us integrating OLS) is solving the same problem: type-aware rules without compiler
    cost. Our M6 approach — delegate to OLS which already has the full type-resolved
    AST — is the right call. Do not build type inference from scratch.

19. **Annotation-driven ownership semantics are mainstream** — Java's JSpecify +
    NullAway is now standard in Spring Framework 7. The concept (opt-in annotations
    that signal ownership/nullability to the linter) is the same as our C012 naming
    conventions. The validation: this pattern is worth enough to major production
    codebases that Google, Uber, and Spring all invested heavily in it.

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
| 5 | OLS plugin | Editor diagnostics + code actions | ✅ |
| 5.5 | MCP gateway | Agent-driven semantic editing + symbol export | ✅ |
| 5.6 | DNA Impact Analysis + Code Graph | SQLite graph, MCP tools, memory roles, find_all_references | 🔧 |
| 6 | Extended rules + Refactoring | C016-C018 naming, C014-C015 dead code, rename_symbol MCP | ✅ |
| 6.5 | Structural rules (B-category) | B001 unmatched brace — token scan, error tier | ✅ |
| 6.6 | C001 FP reduction (AST layer) | Fix escape-hatch bugs, `_init` heuristic, direct delete detection | ✅ |
| 6.7 | C019 type marker suffixes | DEFERRED — needs C012 Phase 2 type inference + convention agreement | ↷ |
| 6.9 | Package-scope linting foundation | Four scope levels defined; B002 package name consistency; B003 subfolder name clash | ✅ |
| 7 | Graph enrichment for LLM + refactoring | Variable roles, proc return types, richer MCP context, C012-T unlock, incremental rebuild | ✅ |
| 7.1 | OLS refactoring + advanced rules | LSP call hierarchy, C101/C201/C202, C012-T, C019 | 🔄 C012-T1+T3 + call hierarchy done |
| 8   | Frejay/agent integration API | errorClass in JSON, lint_workspace, list_rules, get_callers/callees, schema version | ⬜ |

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

---

## 14. Analysis Scope Model

*Added April 2026. This section is the canonical reference for which layer owns
which analysis. Every rule and service must be tagged with its scope. A rule
that accidentally depends on information from a higher scope is either wrong or
must be explicitly promoted.*

---

### The Four Scopes

#### Scope 1 — File

**Unit:** A single `.odin` source file.  
**Available information:** The file's own AST, its token stream, its line text.  
**Not available:** Other files in the package, imported symbols, type resolution.

This is the scope of traditional linting. It is fast, parallelisable, and
requires no coordination between files. Rules at this scope can run on a single
file passed to the CLI (`odin-lint file.odin`) with full correctness.

**Rules at file scope:** C001, C002, C003, C007, C009, C010, C011, C016, C018,
C020, B001.

**Known limitation:** File-scope rules cannot distinguish package-level variables
from local variables when they appear in the same syntactic position. Remaining
C001 false positives from init-and-hold patterns (`foo = make(...)` where `foo`
is package-level) are accepted as a file-scope limitation. Use
`// odin-lint:ignore C001` for intentional package-level allocations in
non-`_init` procs.

---

#### Scope 2 — Package

**Unit:** All `.odin` files in one directory that share the same `package`
declaration.  
**Available information:** Everything in Scope 1, plus: the full symbol namespace
of the package (all top-level declarations across all files), cross-file
`package`-name consistency.  
**Not available:** Symbols from other packages (require explicit import).

In Odin, the package is the fundamental compilation unit. A variable declared in
`graphics_a.odin` is visible in `graphics_b.odin` without import — they share
one namespace. Subfolders are always separate packages regardless of name.

Rules at this scope require the CLI to group files by directory before analysis.
The `PackageContext` struct carries the shared namespace and is passed to rules
that need it.

**Rules at package scope:** B002 (package name consistency), B003 (subfolder
name clash), C017 (package-level naming — needs to see all package-level vars).

**Odin-specific package rules:**
- All files in a directory MUST share the same `package` name — different names
  are a compiler error (→ B002 ERROR).
- `package foo_test` is a valid sibling of `package foo` for test files.
- Subfolders are separate packages; sharing a parent's package name is almost
  always a mistake (→ B003 WARNING).

---

#### Scope 3 — Project

**Unit:** All packages in the project, including cross-package call graph and
symbol index.  
**Available information:** Full symbol graph (nodes + edges), memory roles,
call hierarchy, all references.  
**Not available:** External library internals; runtime type resolution.

This is the scope of the DNA graph (`dna_exporter.odin` + SQLite DB). It answers
questions that no individual file or package can answer alone: "what calls this
proc?", "what is the memory role of this symbol across the whole project?",
"what is the impact radius of renaming this function?".

Project-scope analysis requires `--export-symbols` to have been run first. It is
not fast enough for file-by-file linting and is explicitly NOT wired into the
per-file lint path. It is a **separate service** consumed by:
- MCP tools (`get_dna_context`, `find_allocators`, `get_impact_radius`)
- Refactoring tools (`rename_symbol`, LSP call hierarchy)
- C012-T rules (which require `memory_role` across the project)

**Services at project scope:** DNA graph, all MCP graph tools, C014/C015 (dead
code — require seeing all callers), C012-T.

**Critical distinction:** Linting rules that require project-scope information
are **not linting rules** — they are semantic analysis services. They live in
the MCP/OLS layer, not in the file-by-file lint pipeline.

---

#### Scope 4 — External / FFI

**Unit:** Vendored dependencies, C static libraries, tree-sitter grammars, OLS
fork.  
**Available information:** Public API surface only (header files, exported
symbols).  
**Analysis policy:** External code is excluded from all linting rules by default.
The `--include-vendor` flag overrides this for vendored Odin code only.

**Rules that operate at the FFI boundary:** C011 (FFI resource safety — checks
*our* code's use of C resources, not the C library itself). The rule fires when
our code acquires a C resource (`ts_parser_new()`, etc.) without a matching
`defer ts_parser_delete()`. The C library's internals are opaque.

---

### Scope Assignment Reference

| Rule | Scope | Rationale |
|------|-------|-----------|
| C001 | File | AST walk within one file; cross-file limitation accepted |
| C002 | File | Double-free detection within one file |
| C003/C007 | File | Name conventions visible from declaration alone |
| C009/C010 | File | Import and API deprecation, per-file |
| C011 | File (FFI boundary) | Our code's use of C resources |
| C014/C015 | Project | Dead code requires seeing all callers across all packages |
| C016 | File | Local variable naming |
| C017 | Package | Package-level variable naming (needs all files in package) |
| C018 | File | Proc visibility naming, visible from declaration |
| C019 | Package + types | Type-suffix conventions; requires type inference (deferred) |
| C020 | File | Short variable name warning |
| B001 | File | Token-level brace balance |
| B002 | Package | Package name consistency across files in directory |
| B003 | Package | Subfolder package name clash with parent |
| C012-T | Project | Type-gated ownership naming; requires `memory_role` graph |
| DNA graph | Project | Full symbol index, memory roles, call graph |
| MCP tools | Project | Query layer over DNA graph |
| rename_symbol | Project | Cross-file FixEdit generation |
| LSP call hierarchy | Project | OLS-mediated cross-package navigation |

---

### Why These Scopes Matter

**For rule authors:** Before implementing a rule, identify its scope. A file-scope
rule that reads from the DNA graph is architecturally wrong — it creates a hidden
dependency on a separately-built artefact and breaks `odin-lint single_file.odin`.

**For performance:** File-scope rules run in parallel, one goroutine per file.
Package-scope rules run after grouping but before the file passes. Project-scope
services run separately, on demand, not during the lint pass.

**For OLS plugin:** The plugin runs file-scope rules only (no graph DB access on
every keystroke). Package-scope rules run when the user saves and OLS decides to
re-analyse the package. Project-scope tools are available via MCP, not via the
diagnostic stream.

**For C001 false positives:** The remaining FPs after M6.6 (custom allocator
variables like `path_scratch := g2d_get_path_scratch()`) require **return-type
tracking** — a project-scope / type-resolution capability. They are correctly
handled by suppression comments, not by extending file-scope C001 analysis.

---

*Version: 7.6*
*Last status review: April 21 2026*
*Previous version: odin-lint-implementation-planV6.md (V7.0 was the internal draft)*
