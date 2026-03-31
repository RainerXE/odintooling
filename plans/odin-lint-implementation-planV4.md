# odin-lint — Implementation Plan (v4)
*A Super Linter for the Odin Programming Language*
*Version 4.0 · March 2026 — Updated after full codebase review*

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Honest Milestone Status](#2-honest-milestone-status)
3. [Current Work: Milestone 2 — OLS Wiring](#3-current-work-milestone-2)
4. [Milestone 3 — Real Rule Analysis](#4-milestone-3-real-rule-analysis)
5. [Milestone 4 — Standalone CLI + Tree-sitter](#5-milestone-4-standalone-cli)
6. [Milestone 5 — Additional Rules + AI Integration](#6-milestone-5)
7. [Gates](#7-gates)
8. [AST Strategy](#8-ast-strategy)
9. [FFI Integration](#9-ffi-integration)
10. [Testing](#10-testing)
11. [Build System](#11-build-system)

---

## 1. Folder Structure

```
odin-lint/
├── artifacts/                    # All build outputs (executables, libraries)
├── build/                        # Odin-based build system
├── docs/                         # Documentation and references
│   └── ODIN_STYLE_GUIDE_v2.md     # Style guide reference
├── ffi/                          # C libraries that are part of our solution
│   └── tree_sitter/              # Tree-sitter integration
│       ├── tree-sitter-api.h
│       ├── tree_sitter.h
│       └── tree-sitter-lib/       # submodule
│           └── tree-sitter-odin/  # submodule
├── plans/                        # Planning files (single source of truth)
│   ├── odin-lint-implementation-planV4.md  # Primary plan
│   ├── odin-lint-ols-integration-plan.md  # OLS-specific plan
│   ├── ols-plugin-system-analysis.md      # OLS plugin analysis
│   ├── treesitter-integration-plan.md     # Tree-sitter integration
│   └── REF_AGENT_PROMPT_MILESTONE2.md     # Agent prompt reference
├── scripts/                      # All scripts
│   ├── build.sh                          # Main build script
│   ├── build_external_tree_sitter.sh     # Tree-sitter build
│   ├── build_plugin.sh                   # Plugin build
│   ├── scripts.md                        # Build documentation
│   └── ... (other build scripts)
├── src/                          # Source code
│   ├── core/
│   │   ├── main.odin              # CLI entry point
│   │   ├── ast.odin               # AST types + walker
│   │   ├── tree_sitter.odin       # tree-sitter FFI
│   │   ├── tree_sitter_bindings.odin # FFI bindings
│   │   ├── c001.odin              # C001 rule
│   │   ├── c002.odin              # C002 rule
│   │   ├── plugin_main.odin       # .dylib entry point
│   │   └── integration.odin       # OLS plugin integration
│   ├── rules/
│   │   └── correctness/
│   │       ├── c001.odin          # Rule using ^ast.File (OLS path)
│   │       ├── c002.odin
│   │       └── ...c003-c008.odin
│   └── integrations/
│       └── ols/                   # OLS plugin glue code
├── test/                         # All tests
│   ├── fixtures/
│   │   ├── pass/
│   │   └── fail/
│   └── unit/
└── vendor/                       # External Odin projects
    └── ols/                       # OLS fork with plugin system
        ├── ols.json              # OLS project file
        ├── README.md            # OLS documentation
        └── src/
            └── server/
```
│           ├── plugin.odin        # OLSPlugin interface ✅
│           ├── plugin_manager.odin # Lifecycle management ✅ (gaps to fix)
│           └── plugin_dynamic.odin # dynlib loading ✅ (gaps to fix)
├── artifacts/
│   ├── odin-lint             # standalone CLI binary
│   └── odin-lint-plugin.dylib # OLS plugin shared library
├── build/
├── scripts/
├── test/
│   └── fixtures/
│       ├── pass/
│       └── fail/
└── plans/
```


---

## 2. Honest Milestone Status

### ✅ Milestone 0 — Foundation (COMPLETE)

All gate 0 criteria met:
- CLI skeleton with `odin-lint <file>`, exit codes 0/1
- Diagnostic emitter with `file:line:col [rule] message` format
- Stub rule (STUB001) fires on `TODO_FIXME` identifier
- Test fixtures: `pass/empty.odin`, `fail/todo_fixme.odin`
- Build script working

### ⚠️ Milestone 1 — AST Integration (PARTIALLY COMPLETE)

**What is genuinely done:**
- `ASTNode` struct with position metadata
- `walkAST` / `visitAST` traversal skeleton
- C001 and C002 rule _structure_ (matcher/message/fix_hint pattern)
- FFI directory structure with tree-sitter headers
- tree-sitter git submodules added

**What is NOT done (plan overstated):**
- tree-sitter FFI bindings return `false` from every function
- `initTreeSitterParser()` always fails — `ok = false`
- `parseFile()` therefore always fails
- C001 and C002 matchers operate on a fake placeholder `ASTNode{}`
  with `node_type = "placeholder"` and no children
- The rules detect nothing in real code
- Gate 1 criterion "AST-based linter works with zero false positives"
  is NOT met because the linter doesn't analyse anything

**Corrected status: Milestone 1 infrastructure exists; analysis does not work.**

### ⚠️ Milestone 1B — OLS Plugin System (PARTIALLY COMPLETE)

**What is genuinely done:**
- `OLSPlugin` struct interface in `vendor/ols/src/server/plugin.odin`
- `PluginManager` lifecycle in `plugin_manager.odin`
- `platform_load_plugin` / `platform_get_function` in `plugin_dynamic.odin`
- `DiagnosticType` enum exists in `diagnostics.odin`
- odin-lint builds as `.dylib`; simple test plugin loads successfully

**What is NOT done:**
- `initialize_plugins()` never called in `main.odin`
- `analyze_with_plugins()` never called from document pipeline
- `load_plugin_library()` in `plugin_manager.odin` still simulates
  (doesn't call `platform_load_plugin`)
- No `DiagnosticType.Plugin` enum member
- `PluginDiagnostic` and `Diagnostic` types not reconciled

**Corrected status: Plugin system designed; not yet wired into OLS.**

---

## 3. Current Work: Milestone 2 — OLS Wiring 🔄

**Goal:** Full path from "file saved in editor" → odin-lint plugin called
→ diagnostic appears in editor. A hard-coded test diagnostic is acceptable
at this stage. Real rule analysis comes in Milestone 3.

### Tasks (in order — each is a prerequisite for the next)

**2.1 — Connect `load_plugin_library` to `platform_load_plugin`**
File: `vendor/ols/src/server/plugin_manager.odin`
- Replace simulation with real `platform_load_plugin()` call
- Add symbol resolution via `dynlib.symbol_address("get_odin_lint_plugin")`
- Wire returned proc pointer into `OLSPlugin` struct

**2.2 — Add `DiagnosticType.Plugin`**
File: `vendor/ols/src/server/diagnostics.odin`
- Extend enum: `DiagnosticType :: enum { Syntax, Unused, Check, Plugin }`

**2.3 — Initialise `PluginManager` in OLS startup**
File: `vendor/ols/src/main.odin`
- Create `plugin_manager` as package-level state in `server` package
- Call `initialize_plugins()` after logger is set up
- Call `shutdown_plugins()` on exit via `defer`

**2.4 — Call `analyze_with_plugins` in document pipeline**
File: `vendor/ols/src/server/documents.odin`
- Find where `add_diagnostics(.Syntax, ...)` is called after parse
- Add `analyze_with_plugins()` call and feed results to `.Plugin` bucket

**2.5 — Resolve `PluginDiagnostic` vs `Diagnostic` type mismatch**
File: `vendor/ols/src/server/plugin.odin` + `types.odin`
- Extend native `Diagnostic` with optional `rule_id`, `fix_suggestion` fields
- Remove `PluginDiagnostic` type

**2.6 — Implement `get_odin_lint_plugin` export in odin-lint**
File: `src/core/plugin_main.odin`
- Export `get_odin_lint_plugin :: proc "c" () -> ^OLSPlugin`
- Return static `OLSPlugin` struct with placeholder `analyze_file` that
  returns one hard-coded test diagnostic

### Gate 2 (Wiring)
- [ ] OLS log: `"[PluginManager] Loaded plugin 'odin-lint'"` at startup
- [ ] Opening a `.odin` file: plugin `analyze_file` is called (log confirms)
- [ ] A diagnostic with `source: "odin-lint"` appears in editor Problems panel
- [ ] Zero crashes when plugin is not configured (graceful no-op)


---

## 4. Milestone 3 — Real Rule Analysis via OLS AST 🔜

**Goal:** C001 fires on genuine violations using the `^ast.File` that OLS
provides. No tree-sitter required for this milestone.

**Critical insight:** The OLS plugin receives `^ast.File` (from
`core:odin/ast`) — the same AST Odin's own compiler uses. Rules written
for the OLS plugin path use `ast.walk()` and the `ast.Visitor` pattern,
not tree-sitter. This is simpler and more accurate.

### Tasks

**3.1 — Implement C001 using `^ast.File`**
File: `src/rules/correctness/c001.odin` (new, separate from CLI version)
- Walk `ast.File` for `ast.Call_Expr` where callee is `make` or `new`
- Check enclosing `ast.Block_Stmt` for a `ast.Defer_Stmt` containing
  `free` or `delete` called on the same identifier
- Return `Diagnostic` with correct source range from `node.pos`/`node.end`

**3.2 — Implement C002 using `^ast.File`**
- Detect `defer free(x)` where `x` was allocated as a different type
  (e.g., `buf := make([]u8, n); defer free(&buf)` — wrong target)

**3.3 — Wire rules into `analyze_file` in the plugin**
File: `src/core/integration.odin`
- Replace hard-coded test diagnostic with real rule calls
- Collect and merge diagnostics from each rule

**3.4 — Fixture validation**
- `test/fixtures/fail/c001_allocation.odin` must trigger C001
- `test/fixtures/pass/c001_proper_free.odin` must not trigger C001
- Run both fixtures against OLS + plugin in VS Code to verify

### Gate 3 (Real Analysis)
- [ ] C001 fires on `test/fixtures/fail/c001_allocation.odin`
- [ ] C001 silent on `test/fixtures/pass/c001_proper_free.odin`
- [ ] C002 fires on `test/fixtures/fail/c002_double_free.odin`
- [ ] Zero false positives on `vendor/ols/src/` (run against OLS codebase)
- [ ] Diagnostic position (line/col) is correct in editor squiggle

---

## 5. Milestone 4 — Standalone CLI + Tree-sitter 🔜

**Goal:** `odin-lint <file>` works without OLS. This requires tree-sitter
because the CLI has no access to OLS's parser.

The OLS plugin and the CLI are **two separate analysis paths**:

| Path | AST source | Status |
|------|-----------|--------|
| OLS plugin | `^ast.File` from OLS | Milestones 2–3 |
| Standalone CLI | tree-sitter via FFI | This milestone |

### Tasks

**4.1 — Implement real tree-sitter FFI bindings**
File: `src/core/tree_sitter.odin`
- Build `libtree-sitter.a` and `tree-sitter-odin` grammar library
- Write real `foreign import` declarations
- Implement `ts_parser_new`, `ts_parser_set_language`,
  `ts_parser_parse_string`, `ts_node_type`, `ts_node_start_point` etc.
- Remove all placeholder stubs

**4.2 — Implement `parseFile` using real tree-sitter**
- Parse file content into a real `TSTree`
- Walk tree nodes and populate `ASTNode` structs with real data

**4.3 — Port C001 rule to use real `ASTNode` from tree-sitter**
- Replace `strings.contains(node.node_type, "make")` text matching
  with proper node type checks (`"call_expression"` + callee identity)

**4.4 — Archive `src/core/lsp_server.odin`**
- Move to `archive/lsp_server.odin.bak`
- Remove from build — standalone LSP server is the wrong architecture

### Gate 4 (Standalone CLI)
- [ ] `odin-lint test/fixtures/fail/c001_allocation.odin` exits 1 with C001
- [ ] `odin-lint test/fixtures/pass/c001_proper_free.odin` exits 0
- [ ] `odin-lint` on a 500-line Odin file completes in under 2 seconds
- [ ] No memory leaks (tree-sitter resources freed via defer)

---

## 6. Milestone 5 — Additional Rules + AI Integration 🔜

**Goal:** Implement C003–C008 and expose AST for AI agent consumption.

### Correctness Rules (C003–C008)

| Rule | Pattern | AST approach |
|------|---------|-------------|
| C003 | `context.allocator` swapped but not restored | Walk proc body for assign to `context.allocator`; check all return paths |
| C004 | Unreachable code after `return`/`break` | Detect stmts after `ast.Return_Stmt` in same block |
| C005 | Variable shadowing | Symbol table across nested scopes |
| C006 | Loop variable captured in proc literal | Detect `ast.Proc_Lit` inside `ast.For_Stmt` referencing loop var |
| C007 | Narrowing integer cast without check | `ast.Cast_Expr` where target type is smaller |
| C008 | Slice index without bounds guard | `ast.Index_Expr` on slice without preceding length check |

### AI Integration (`--ast=json` flag)

```sh
odin-lint --ast=json src/main.odin > ast.json
```

Emits the parsed AST as JSON for consumption by AI coding agents.
This is separate from the lint pipeline — purely an export feature.

### Gate 5
- [ ] All 8 correctness rules implemented with 3 pass + 3 fail fixtures each
- [ ] Zero false positives on `vendor/ols/src/` and `odin/core/` stdlib
- [ ] `--ast=json` flag produces valid, parseable JSON

---

## 7. Gates Summary

| Gate | Milestone | Key Criterion |
|------|-----------|--------------|
| 0 | Foundation | CLI works, stub rule fires, test harness functional |
| 1 | AST infra | ~~AST-based linter works~~ → **Deferred to Gate 3** |
| 2 | OLS wiring | Hard-coded plugin diagnostic appears in editor |
| 3 | Real analysis | C001+C002 fire on real code, zero false positives |
| 4 | Standalone CLI | tree-sitter wired, CLI works without OLS |
| 5 | Full rule set | 8 correctness rules, all fixtures pass |

*Note: Gate 1 from v3 plan was incorrectly marked as passed. The AST
infrastructure exists but tree-sitter is a placeholder. Real AST analysis
is now Gate 3 (OLS path) and Gate 4 (CLI path).*


---

## 8. AST Strategy

### Two Paths, Two AST Sources

This is the most important architectural decision in the project:

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
│  Walk:   manual node traversal                      │
│  Rules:  src/core/c001.odin etc. (tree-sitter vers) │
│  When:   odin-lint <file> from terminal / CI        │
└─────────────────────────────────────────────────────┘
```

Rules are written twice — once per path — because the AST types differ.
This is acceptable: the logic is identical, only the node access API
differs. Shared helper procs (e.g., `is_allocation_call`) can be factored
out into a common package.

### Why NOT use tree-sitter in the OLS plugin?

- OLS already parsed the file — duplicate parsing wastes time
- `^ast.File` is richer than tree-sitter: it has full type info, resolved
  identifiers, and scope data that OLS computes
- Avoids a C FFI dependency inside the plugin `.dylib`
- Simpler to maintain: `ast.walk()` is idiomatic Odin

### Why NOT use `^ast.File` in the CLI?

- The standalone CLI doesn't link against OLS
- Invoking Odin's compiler frontend programmatically is fragile and
  unsupported
- tree-sitter is the standard solution for standalone analysis tools

---

## 9. FFI Integration

### Scope

FFI (tree-sitter via C bindings) is only required for the standalone CLI.
The OLS plugin has no FFI dependency.

### tree-sitter Binding Plan

```odin
// src/core/tree_sitter.odin — real bindings (replaces current stubs)
foreign import ts "tree_sitter/libtree-sitter.a"
foreign import ts_odin "tree_sitter/libtree-sitter-odin.a"

TSNode :: struct { /* opaque */ ctx: [4]rawptr, id: rawptr }
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
    ts_node_child          :: proc(node: TSNode, child_index: u32) -> TSNode ---
    ts_node_string         :: proc(node: TSNode) -> cstring ---
}

@(default_calling_convention = "c")
foreign ts_odin {
    tree_sitter_odin :: proc() -> rawptr ---
}
```

### Review Process

Before adding any new C library binding:
1. Add header to `ffi/<library>/`
2. Document in `ffi/review/c_interface_review.md`:
   - Purpose, C header, Odin wrapper file
   - Each function: signature, memory ownership, thread safety
3. Verify with a minimal standalone test before wiring into rules

---

## 10. Testing

### Fixture Requirements (per rule)

Each rule needs at minimum:
- 3 `test/fixtures/pass/<rule>/` files — must produce zero diagnostics
- 3 `test/fixtures/fail/<rule>/` files — must produce exactly the documented diagnostic
- Snapshot file: expected stdout output for each fail fixture

### Current Fixture Status

| Rule | Pass fixtures | Fail fixtures | Real analysis? |
|------|--------------|--------------|----------------|
| C001 | 1 (empty) | 1 | ❌ placeholder AST |
| C002 | 1 | 1 | ❌ placeholder AST |
| STUB001 | 1 | 1 | ✅ text scan |

### Test Runner

```bash
scripts/test_rules.sh        # Run all fixtures, compare to snapshots
scripts/test_ols.sh          # Test OLS plugin integration
scripts/bench.sh             # Performance benchmark on large file
```

### Integration Test (OLS path)

After Milestone 2 is complete, add an automated test that:
1. Starts OLS with the plugin configured
2. Sends a `textDocument/didOpen` for a fail fixture via LSP JSON-RPC
3. Asserts that a `publishDiagnostics` notification arrives with
   `source: "odin-lint"` and the correct rule code

---

## 11. Build System

### Targets

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

clean:
    rm -f artifacts/odin-lint artifacts/odin-lint-plugin.dylib
```

### Build Flags for Plugin

The plugin `.dylib` must be built with:
- `-build-mode:shared` — produces a shared library
- No conflicting package imports with OLS (both use `core:odin/ast` —
  ensure no symbol collision)

---

*odin-lint Implementation Plan v4 · Built for the Odin community*
