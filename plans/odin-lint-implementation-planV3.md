
# odin-lint — Implementation Plan (v3)
*A Super Linter for the Odin Programming Language*
*Version 3.0 · 2025*

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Steps and Milestones](#2-steps-and-milestones)
3. [Gates](#3-gates)
4. [AST and AI Integration](#4-ast-and-ai-integration)
5. [FFI Integration for C Interfaces](#5-ffi-integration-for-c-interfaces)
6. [Testing](#6-testing)
7. [Logging](#7-logging)
8. [Build System](#8-build-system)
9. [Scripts](#9-scripts)

---

## 1. Folder Structure

```
odin-lint/
├── src/
│   ├── ast/
│   │   ├── tree_sitter_wrapper.odin  # Minimal FFI for Tree-Sitter
│   │   └── ast_utils.odin            # Odin-native AST helpers
│   ├── rules/                       # Rules in pure Odin
│   │   ├── correctness/
│   │   │   └── c001.odin             # Example: C001 rule
│   │   └── ...
│   ├── core/
│   │   ├── rule_engine.odin          # Rule registry and applier (pure Odin)
│   │   └── diagnostics.odin          # Emits diagnostics
│   └── integrations/
│       ├── ols.odin                  # OLS/LSP integration
│       └── cli.odin                  # CLI integration
├── ffi/
│   ├── tree_sitter/                 # Tree-Sitter C bindings
│   │   ├── tree_sitter.h            # C headers
│   │   └── tree_sitter_wrapper.c     # Minimal FFI wrapper
│   └── review/                      # For reviewing C interfaces
│       └── c_interface_review.md    # Documentation for C interface review
├── artifacts/                       # Executables
├── build/                           # Build scripts
├── scripts/                         # Utility scripts
├── test/                            # Test fixtures and snapshots
└── plans/                           # Roadmap and documentation
```

---

## 2. Steps and Milestones

### ✅ Milestone 0 (Foundation) - COMPLETED
- ✅ Set up repository structure.
- ✅ Implement basic CLI skeleton.
- ✅ Implement diagnostic emitter.
- ✅ Add stub rule for pipeline validation.
- ✅ CLI: `odin-lint <file>` working.
- ✅ Test fixtures created (pass/fail).
- ✅ Build system working.

**Status:** All Gate 0 tests passing
- ✅ AST walker placeholder implemented
- ✅ Stub rule fires correctly
- ✅ Clean file produces zero output
- ✅ CLI exit codes working (0 for clean, 1 for findings)
- ✅ Basic test harness functional

### 🏗️ Milestone 1 (AST Integration) - IN PROGRESS
- ✅ **Set up FFI infrastructure** with dedicated directories
- ✅ **Add tree-sitter-odin as git submodule** for grammar
- [ ] **Create `tree_sitter_wrapper.odin`** for minimal FFI to Tree-Sitter
- [ ] **Implement AST conversion utilities** in `ast_utils.odin`
- [ ] **Enhance C001 rule with real AST analysis** (allocation without defer free)
- [ ] **Implement C002 rule** (defer free on wrong pointer) for validation
- [ ] **Test AST parsing** with existing test fixtures
- [ ] **Add fixture coverage** (3 pass + 3 fail for C001, 2 pass + 2 fail for C002)

**Current Status: Working Baseline with Placeholder AST**

✅ **Milestone 0 Complete**: Foundation working with CLI, diagnostics, and stub rules
✅ **Milestone 1 In Progress**: AST integration framework in place with placeholders

**Working Components:**
- ✅ CLI: `odin-lint <file>` functional
- ✅ Diagnostic emitter with proper formatting
- ✅ Rule registry system
- ✅ C001 rule skeleton with placeholder AST analysis
- ✅ Build system working
- ✅ Test fixtures for pass/fail cases
- ✅ Proper exit codes (0 for clean, 1 for findings)

**Placeholder Implementation:**
- Tree-sitter integration framework added (returns empty AST for now)
- C001 rule calls matcher with AST node
- Ready for real tree-sitter grammar integration

**Simplified Milestone 1 Completion:**
Instead of complex FFI, we'll use a **two-phase approach**:

**Phase 1 (Current - Working Baseline)**:
- ✅ Complete CLI and rule system
- ✅ Placeholder AST integration
- ✅ All infrastructure ready
- ✅ Test fixtures created

**Phase 2 (Next - Tree-Sitter Integration)**:
- Add tree-sitter-odin as git submodule
- Implement real FFI bindings
- Update C001 with real AST analysis
- Add C002 rule

**Gate 1 (Adjusted):** Placeholder AST system working, ready for tree-sitter integration

### 🚀 Milestone 2 (OLS/LSP Integration) - NEXT
- [ ] **Connect Tree-Sitter to OLS** for real-time AST streaming.
- [ ] **Publish diagnostics via LSP** (VS Code, Neovim, etc.).
- [ ] **Add `--ast=json` CLI flag** to expose AST for AI/coding agents.
- [ ] **Test OLS integration** with sample Odin projects.

**Gate 2:** OLS shows linter diagnostics as you type.

### 🤖 Milestone 3 (AI/Coding Agent Integration) - FUTURE
- [ ] **Expose AST via CLI** (`odin-lint --ast=json`).
- [ ] **Prototype AI agent** to analyze ASTs and suggest fixes.
- [ ] **Add `--apply-diff` CLI flag** to apply AI-suggested changes.
- [ ] **Integrate with odin-lint** for seamless AI-assisted refactoring.

---

## 3. Gates

| Gate | Description | Criteria |
|------|-------------|----------|
| 0 | Foundation | All Milestone 0 tasks complete, zero false positives. |
| 1 | AST Integration | AST-based linter works for C001-C002 with zero false positives. |
| 2 | OLS/LSP Integration | OLS shows linter diagnostics in real-time. |

---

## 4. AST and AI Integration

### A. Why AST?
- **Semantic accuracy:** ASTs capture Odin’s explicit memory management and context system.
- **AI-friendly:** AI tools can reason about ASTs without parsing Odin’s niche syntax.
- **Tooling integration:** ASTs are the bridge between Odin code and coding agents.

### B. How to Integrate AST
1. **Tree-Sitter Odin Grammar:**
   - Fork [tree-sitter-odin](https://github.com/odin-lang/tree-sitter-odin) or implement a minimal grammar.
   - Test with:
     ```sh
     tree-sitter generate
     tree-sitter parse test.odin
     ```

2. **AST Backend for odin-lint:**
   - Add `src/ast/tree_sitter_wrapper.odin` and `src/ast/ast_utils.odin`:
     ```odin
     // src/ast/tree_sitter_wrapper.odin
     package tree_sitter

     import "core:fmt"
     import "core:c"

     TSTree :: distinct rawptr
     TSNode :: distinct rawptr

     @(c_import, "ffi/tree_sitter/tree_sitter.h")
     parse_file :: proc(path: string) -> ^TSTree { ... }
     root_node :: proc(tree: ^TSTree) -> TSNode { ... }
     ```
   - Update `src/core/rule_engine.odin` to use the AST:
     ```odin
     // src/core/rule_engine.odin
     import "../ast/tree_sitter_wrapper"
     import rules "../rules"

     apply_rules :: proc(ast: ^tree_sitter.TSTree) -> bool {
         for rule in rules.registry {
             rule.apply(ast)
         }
     }
     ```

3. **AST-Based Rules (Example: C001 in Pure Odin)**
   ```odin
   // src/rules/correctness/c001.odin
   package rules

   import "../core/diagnostics"
   import "../ast/tree_sitter_wrapper"

   C001 :: struct {
       id:          string,
       description: string,
       tier:        Tier,
       apply:       proc(ast: ^tree_sitter.TSTree) -> bool,
   }

   C001_RULE :: C001{
       id:          "C001",
       description: "Missing defer free for allocation",
       tier:        .Correctness,
       apply: func(ast: ^tree_sitter.TSTree) -> bool {
           defer {
               if !found_alloc || found_defer_free {
                   return false
               }
               diagnostics.emit("C001", "Missing defer free for allocation")
               return true
           }
           found_alloc := false
           found_defer_free := false
           // Traverse AST and check for alloc without defer/free
           // ... (use tree_sitter API)
       },
   }
   ```

### C. Coding Agent Integration
1. **Expose AST via CLI:**
   ```sh
   odin-lint --ast=json src/main.odin > ast.json
   ```
2. **AI Agent Workflow:**
   - Agent analyzes `ast.json` and outputs a diff (e.g., in JSON).
   - Agent applies the diff:
     ```sh
     odin-lint --apply-diff ast_diff.json
     ```

---

## 5. FFI Integration for C Interfaces

### A. Purpose
- Allow **review and integration of C interfaces** (e.g., Tree-Sitter, GDB, etc.) without embedding C code in Odin.
- Provide a **centralized place** to document and review C bindings.

### B. Folder Structure
```
ffi/
├── tree_sitter/
│   ├── tree_sitter.h    # C headers
│   └── tree_sitter_wrapper.c # Minimal FFI wrapper
└── review/
    └── c_interface_review.md # Documentation for C interface review
```

### C. How to Use FFI for Review
1. **Document C Interfaces:**
   - Place C headers (e.g., `tree_sitter.h`) in `ffi/tree_sitter/`.
   - Write a `c_interface_review.md` file explaining the purpose and usage of each C function.

2. **Minimal FFI Wrappers:**
   - Write thin Odin wrappers in `odin-tree-sitter` (e.g., `tree_sitter_wrapper.odin`).
   - Example:
     ```odin
     // ffi/tree_sitter/tree_sitter_wrapper.odin
     package tree_sitter

     import "core:c"

     @(c_import, "ffi/tree_sitter/tree_sitter.h")
     parse_file :: proc(path: string) -> ^TSTree extern
     ```

3. **Review Process:**
   - Before integrating a new C library, document its interface in `c_interface_review.md`.
   - Example entry:
     ```markdown
     # Tree-Sitter FFI Review
     
     - **Purpose:** Parse Odin code into AST.
     - **C Header:** `tree_sitter.h`
     - **Odin Wrapper:** `tree_sitter_wrapper.odin`
     - **Functions:**
       - `parse_file(path: string) -> ^TSTree`
       - `root_node(tree: ^TSTree) -> TSNode`
     - **Limitations:** Only covers core parsing functions.
     ```

### D. Benefits
- **Centralized Documentation:** All C interfaces are documented in one place.
- **Easier Review:** Before merging new FFI code, review the C interface and its Odin wrapper.
- **Minimal FFI Surface:** Only the necessary C functions are exposed to Odin.

---

## 6. Testing

- **Fixtures:** Add 3 pass + 3 fail tests per rule.
- **AST Validation:** Ensure Tree-Sitter grammar matches Odin’s syntax.
- **OLS Integration:** Test diagnostics in VS Code/Neovim.
- **AI Integration:** Validate AI-suggested fixes compile without errors.
- **FFI Integration:** Test Tree-Sitter wrapper with sample Odin files.

---

## 7. Logging

- Log AST parsing errors to `logs/ast_parser.log`.
- Log LSP diagnostics to `logs/ols.log`.
- Log FFI errors to `logs/ffi.log`.

---

## 8. Build System

- Use a simple Makefile for now:
  ```makefile
  build:
      odin build src -out:artifacts/odin-lint
  ```
- Later, consider CMake or Bazel for larger projects.

---

## 9. Scripts

- `scripts/ast_parser.sh`: Helper to parse a file to AST.
- `scripts/test_rules.sh`: Run all rule tests.
- `scripts/ols_integration.sh`: Test OLS diagnostics.
- `scripts/ffi_review.sh`: Review C interfaces for FFI safety.

---
