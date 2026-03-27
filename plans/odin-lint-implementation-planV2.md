
# odin-lint — Implementation Plan (v2)
*A Super Linter for the Odin Programming Language*
*Version 2.0 · 2025*

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Steps and Milestones](#2-steps-and-milestones)
3. [Gates](#3-gates)
4. [AST and AI Integration](#4-ast-and-ai-integration)
5. [Testing](#5-testing)
6. [Logging](#6-logging)
7. [Build System](#7-build-system)
8. [Scripts](#8-scripts)

---

## 1. Folder Structure

```
odin-lint/
├── src/
│   ├── ast/               # NEW: Tree-Sitter and AST utilities
│   │   ├── parser.c       # Tree-Sitter grammar integration
│   │   └── walker.c       # AST traversal logic
│   ├── core/              # Rule engine (updated to use AST)
│   ├── rules/             # Rule definitions (now AST-aware)
│   │   ├── correctness/   # C001-C008
│   │   └── ...
│   ├── output/            # Formatters (CLI, JSON, LSP)
│   └── integrations/      # OLS, GitHub Action, AI agent
├── artifacts/             # Executables
├── build/                 # Build scripts
├── scripts/               # Utility scripts
├── test/                  # Test fixtures and snapshots
└── plans/                 # Roadmap and documentation
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
- [ ] **Implement `tree-sitter-odin` grammar** (use canonical fork or start from scratch).
- [ ] **Integrate Tree-Sitter as AST backend** in `src/ast/parser.c` and `src/ast/walker.c`.
- [ ] **Update rule engine** to use AST for analysis (e.g., C001: allocation without defer free).
- [ ] **Implement 2-3 AST-based rules** (e.g., C001, C002) to validate the approach.
- [ ] **Test AST parsing** with `tree-sitter parse test.odin`.
- [ ] **Fixture coverage** (3 pass + 3 fail per rule).

**Gate 1:** AST-based linter works for C001-C002 with zero false positives.

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
   - Add `src/ast/parser.c` and `src/ast/walker.c`:
     ```c
     // src/ast/parser.c
     #include "tree_sitter/parser.h"
     extern const TSLanguage *tree_sitter_odin(void);
     
     OdinAST parse_odin_file(const char *path) {
         // Use Tree-Sitter to parse the file
     }
     ```
   - Update `src/core/rule_engine.c` to use the AST:
     ```c
     void apply_rules(const char *path) {
         OdinAST ast = parse_odin_file(path);
         for (Rule *rule = rule_registry; rule != NULL; rule = rule->next) {
             rule->apply(ast, rule->data);
         }
     }
     ```

3. **AST-Based Rules (Example: C001)**
   ```c
   // src/rules/c001.c
   bool rule_c001_apply(OdinAST ast) {
       TSNode root = ast.root;
       bool found_alloc = false;
       bool found_defer_free = false;
       
       ts_node_foreach_child(root, child) {
           if (strcmp(ts_node_type(child), "alloc") == 0) found_alloc = true;
           if (strcmp(ts_node_type(child), "defer") == 0 &&
               strcmp(ts_node_child(child, 0), "free") == 0) found_defer_free = true;
       }
       
       if (found_alloc && !found_defer_free) {
           emit_diagnostic("C001", "Missing defer free for allocation");
           return true;
       }
       return false;
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

## 5. Testing

- **Fixtures:** Add 3 pass + 3 fail tests per rule.
- **AST Validation:** Ensure Tree-Sitter grammar matches Odin’s syntax.
- **OLS Integration:** Test diagnostics in VS Code/Neovim.
- **AI Integration:** Validate AI-suggested fixes compile without errors.

---

## 6. Logging

- Log AST parsing errors to `logs/ast_parser.log`.
- Log LSP diagnostics to `logs/ols.log`.

---

## 7. Build System

- Use a simple Makefile for now:
  ```makefile
  build:
      gcc -o artifacts/odin-lint src/ast/parser.c src/core/rule_engine.c ...
  ```
- Later, consider CMake or Bazel for larger projects.

---

## 8. Scripts

- `scripts/ast_parser.sh`: Helper to parse a file to AST.
- `scripts/test_rules.sh`: Run all rule tests.
- `scripts/ols_integration.sh`: Test OLS diagnostics.

---
