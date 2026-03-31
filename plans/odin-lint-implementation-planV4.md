# odin-lint — Implementation Plan (v4)
*A Super Linter for the Odin Programming Language*
*Version 4.0 · March 2026 — Updated after full codebase review*

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Honest Milestone Status](#2-honest-milestone-status)
3. [Current Work: Milestone 2 — Grammar Update & Rule Implementation](#3-current-work-milestone-2)
4. [Milestone 3 — Complete CLI Rule Set](#4-milestone-3-complete-cli-rule-set)
5. [Milestone 4 — OLS Plugin Integration](#5-milestone-4-ols-plugin-integration)
6. [Milestone 5 — Advanced Features](#6-milestone-5-advanced-features)
7. [Gates](#7-gates)
8. [AST Strategy](#8-ast-strategy)
9. [FFI Integration](#9-ffi-integration)
10. [Testing](#10-testing)
11. [Build System](#11-build-system)
12. [Tree-sitter Grammar Update Strategy](#12-tree-sitter-grammar-update-strategy)

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
├── tests/                        # All tests
│   ├── archive/                  # Historical OLS tests
│   ├── fixtures/
│   │   ├── pass/
│   │   └── fail/
│   ├── error.odin                # Simple test file
│   └── test.odin                 # Basic test file
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

### ✅ Milestone 1 — CLI Tree-sitter Integration (COMPLETED)

**What is genuinely done:**
- `ASTNode` struct with position metadata exists
- Basic rule structure (C001, C002) is defined
- Tree-sitter libraries are built (`libtree-sitter.a`)
- FFI bindings are properly implemented in `tree_sitter_bindings.odin`
- **CRITICAL FIX**: TSNode correctly defined as 24-byte struct (not pointer)
- Tree-sitter language loading works (Odin grammar from `libtree-sitter-odin.a`)
- Real file parsing implemented using tree-sitter FFI
- CLI can successfully parse real Odin files without crashing

**What is working (verified):**
- ✅ `initTreeSitter()` successfully initializes parser and loads Odin language
- ✅ `parseSource()` can parse real Odin files using tree-sitter
- ✅ `getRootNode()` returns valid root node from parsed tree
- ✅ `convertToASTNode()` converts tree-sitter nodes to our AST format
- ✅ CLI can analyze real Odin code and generate diagnostics
- ✅ No crashes on valid Odin files
- ✅ Proper exit codes and error handling

**Honest status: CLI is now functional. Tree-sitter FFI works correctly. Real linting functionality is operational.**

### ⚠️ Milestone 1B — OLS Plugin System (DEPRIORITIZED - WRONG PRIORITY)

**IMPORTANT CORRECTION**: This milestone has been deprioritized. The OLS plugin system should NOT be worked on until the CLI is fully functional with a complete rule set. This was a strategic error in the original planning.

**Current Status**: Plugin system exists but is incomplete and should remain on hold.

**When to resume**: Only after Milestone 3 (Complete CLI Rule Set) is achieved. The CLI must be production-ready before OLS integration.

**Rationale**:
- CLI is the foundation - must be fully functional first
- OLS integration depends on working rules and stable CLI
- Tree-sitter grammar needs updating before OLS work
- Current OLS plugin system is unfinished and should not be prioritized

---

## 3. Current Work: Milestone 2 — Grammar Update & Rule Implementation

**Goal:** Update the outdated tree-sitter Odin grammar and implement real linting rules.
This is the correct priority - CLI must be fully functional before OLS integration.

**Priority Correction:** OLS integration (Milestone 4) is deprioritized. Focus is now on:
1. Updating the 2-year-old Odin grammar
2. Implementing comprehensive rule set
3. Making CLI production-ready

### Tasks (in order — each is a prerequisite for the next)

**2.1 — Verify Tree-sitter Odin Grammar Completeness ✅ COMPLETED**
**RESULT**: Grammar is complete and functional - no update needed

**Verification Performed**:
- ✅ Tested grammar against 7 different Odin core library categories
- ✅ 100% success rate parsing real Odin source code
- ✅ Verified FFI syntax support (critical for our use case)
- ✅ Confirmed modern Odin features work correctly
- ✅ Grammar from Dec 2024 is sufficiently current

**Files Tested Successfully**:
- `bufio/lookahead_reader.odin` - I/O operations
- `fmt/fmt.odin` - Formatting functions
- `mem/raw.odin` - Memory management
- `os/file_posix_other.odin` - OS functions
- `math/ease.odin` - Math operations
- `strconv/decimal.odin` - String conversion
- `time/time_windows.odin` - Time handling

**Conclusion**: Grammar is production-ready. No updates required.

**2.2 — Implement Real C001 Rule (Memory Allocation)**
File: `src/core/c001.odin`
- Replace placeholder with real AST traversal
- Detect `make`/`new` allocations in tree-sitter AST
- Check for matching `defer free` in same scope
- Generate real diagnostics with correct positions
- Test with real Odin code examples

**2.3 — Implement Real C002 Rule (Defer Free Issues)**
File: `src/core/c002.odin`
- Replace string matching with real AST analysis
- Detect defer free on wrong pointer types
- Use actual node types and relationships
- Generate accurate diagnostics
- Test with real Odin code examples

**2.4 — Implement Additional Core Rules (C003-C008)**
- C003: Inconsistent naming conventions
- C004: Private procedure naming violations
- C005: Internal procedure naming violations
- C006: Public procedure naming violations
- C007: Type naming violations (must be PascalCase)
- C008: Acronym consistency violations

**2.5 — CLI Enhancements**
- Implement proper `--help` flag handling
- Add `--list-rules` flag to show available rules
- Improve error messages and exit codes
- Add JSON output format for tool integration

### Gate 2 (CLI with Real Rules)
- [ ] Tree-sitter Odin grammar updated to latest version
- [ ] C001 detects real allocation issues in test files
- [ ] C002 detects real defer free issues in test files
- [ ] At least 4 additional rules implemented (C003-C006)
- [ ] `--help` and `--list-rules` flags working
- [ ] CLI can analyze real Odin projects
- [ ] No false positives on valid Odin code


---

## 4. Milestone 4 — OLS Plugin Integration (DEPRIORITIZED - CORRECT PRIORITY)

**Status:** This milestone is deprioritized until CLI is fully functional.
OLS integration cannot proceed until the CLI has a complete rule set and is production-ready.

**Rationale:**
- CLI must be fully functional first (Milestones 2-3)
- OLS plugin depends on working rules and stable CLI
- Tree-sitter grammar needs updating before OLS work
- Current OLS plugin system is unfinished and should not be prioritized

**When to resume:** Only after Gate 3 (Production-Ready CLI) is achieved.

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

## 5. Milestone 3 — Full CLI Rule Set + Style Enforcement 🔜

**Goal:** Implement comprehensive rule set including style guide enforcement.
This milestone turns odin-lint into a complete linting tool.

**Prerequisite:** Gate 1 (CLI Working) must be achieved first.

**Scope:**
- Complete all 8+ correctness rules (C001-C019)
- Add style guide enforcement rules
- Comprehensive test coverage
- Production-ready CLI tool

### Tasks

**3.1 — Implement remaining correctness rules (C003-C008)**
- **C003**: Inconsistent naming conventions
- **C004**: Private procedure naming violations
- **C005**: Internal procedure naming violations  
- **C006**: Public procedure naming violations
- **C007**: Type naming violations (must be PascalCase)
- **C008**: Acronym consistency violations

**3.2 — Implement style guide enforcement rules**
- **C009**: Boolean naming violations (no negatives)
- **C010**: Pointer parameter naming inconsistencies
- **C011**: Unchecked pointer dereferencing
- **C012**: Missing nil checks
- **C013**: Undocumented optional pointers

**3.3 — Implement error handling rules**
- **C014**: Ignored error returns
- **C015**: Inconsistent error propagation
- **C016**: Missing error context

**3.4 — Complete rule infrastructure**
- Rule registry system for all 16+ rules
- Unified diagnostic reporting
- Rule configuration system
- Rule suppression comments (// odin-lint:disable C001)

**3.5 — Comprehensive test fixtures**
- Create `test/fixtures/fail/` for each rule
- Create `test/fixtures/pass/` for each rule
- Test against real Odin codebases
- Performance testing on large files

**3.6 — CLI enhancements**
- `--list-rules` flag to show available rules
- `--enable/--disable` flags for rule selection
- `--config` flag for rule configuration
- JSON output format for tool integration

### Gate 3 (Full CLI)
- [ ] All 16+ rules implemented and tested
- [ ] `odin-lint --list-rules` shows all available rules
- [ ] Each rule has 3+ pass and 3+ fail test fixtures
- [ ] Zero false positives on `odin/core/` stdlib
- [ ] CLI completes in under 1s on 1000-line files
- [ ] JSON output format works for tool integration

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
| 0 | Foundation | ✅ CLI skeleton, stub rule, basic build |
| 1 | CLI Fix | ❌ Real tree-sitter parsing, C001/C002 working |
| 2 | OLS Plugin | ⏸ Deprioritized until CLI works |
| 3 | Full CLI | 🔜 16+ rules, style enforcement, production-ready |
| 4 | OLS Integration | 🔜 Plugin system with real analysis |
| 5 | Advanced Features | 🔜 AI integration, custom rules, IDE plugins |

**Updated Rule Plan:**
- **Correctness Rules (C001-C008):** Memory safety, allocation patterns
- **Style Rules (C009-C016):** Naming conventions, consistency enforcement
- **Total:** 16+ rules covering correctness and style

**Corrected Priority (UPDATED):**
- **Current Focus:** Gate 2 (Rule Implementation) - Implement real linting rules
- **Next Phase:** Gate 3 (Complete CLI) - Full rule set + production features
- **Deprioritized:** OLS integration (Gate 4) until CLI is production-ready
- **Honest Status:** Gate 1 ✅ COMPLETED, Grammar ✅ VERIFIED, now implementing rules


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

## 12. Tree-sitter Grammar Update Strategy

### Problem Statement

The tree-sitter Odin grammar in `ffi/tree_sitter/tree-sitter-odin/` is approximately **2 years old**. During this time:
- Odin language has evolved with new syntax features
- Tree-sitter library has had updates and bug fixes
- Our grammar may not support current Odin syntax
- This could cause parsing errors or missing syntax elements

### Update Strategy

**Step 1: Version Assessment**
- Check current Odin language version (from odin compiler)
- Check tree-sitter-odin grammar version (from grammar repository)
- Check tree-sitter library version (from our build)
- Identify compatibility gaps

**Step 2: Grammar Update**
- Fork/update the tree-sitter-odin grammar repository
- Merge latest changes from upstream
- Test grammar with current Odin syntax
- Fix any parsing issues

**Step 3: Rebuild Static Library**
```bash
cd ffi/tree_sitter/tree-sitter-odin
# Update grammar files
git pull upstream main
# Rebuild static library
make
# Copy to our project
cp libtree-sitter-odin.a ../../tree-sitter-lib/
```

**Step 4: Integration Testing**
- Test with our CLI: `./odin-lint test.odin`
- Verify all syntax elements parse correctly
- Test with complex Odin code (structs, generics, etc.)
- Check for any parsing regressions

**Step 5: Fallback Plan**
If grammar update causes issues:
- Keep old grammar as backup
- Implement gradual update strategy
- Add version compatibility checks

### Grammar Maintenance Plan

**Going Forward:**
- Schedule quarterly grammar updates
- Automate grammar version checking
- Add grammar update to CI/CD pipeline
- Monitor Odin language changes

### Critical Dependencies

- Tree-sitter library version compatibility
- Odin language syntax stability
- Grammar repository maintenance

---

*odin-lint Implementation Plan v4 · Corrected Priority · Built for the Odin community*
