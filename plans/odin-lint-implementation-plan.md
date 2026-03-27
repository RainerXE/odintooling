# odin-lint — Implementation Plan
*A Super Linter for the Odin Programming Language*
*Version 1.0 · 2025*

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Steps and Milestones](#2-steps-and-milestones)
3. [Gates](#3-gates)
4. [Testing](#4-testing)
5. [Logging](#5-logging)
6. [Build System](#6-build-system)
7. [Scripts](#7-scripts)

---

## 1. Folder Structure

```
odin-lint/
├── src/
│   ├── core/              # Rule engine
│   ├── rules/             # Rule definitions
│   ├── output/            # Formatters (CLI, JSON, LSP)
│   └── integrations/      # OLS, GitHub Action
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

### 🏗️ Milestone 1 (Correctness Tier) - IN PROGRESS
- ✅ Rule registry and isolation system implemented.
- ✅ C001 rule skeleton created (allocation without defer free).
- [ ] Implement remaining 7 correctness rules (C002-C008).
- [ ] Fixture coverage (3 pass + 3 fail per rule).
- [ ] Documentation for each rule.
- [ ] Ensure zero false positives.

**Current Focus:** Implementing tree-sitter integration for AST parsing

**Progress:**
- ✅ Rule system architecture working
- ✅ C001 rule integrated and functional
- ✅ Rule registry can manage multiple rules
- ✅ Basic rule application pipeline working

### Milestone 2 (Config + Suspicious/Style Tiers)
- Add `odin-lint.toml` config parser.
- Implement 5 suspicious and 4 style rules.
- JSON output mode.
- Path exclusion logic.
- `--explain` flag for rule details.

### Milestone 3 (OLS Integration + Auto-fix)
- Implement `--lsp-mode` for OLS.
- Auto-fix for 4 rules.
- Test OLS integration in VS Code and Neovim.
- Ensure fix safety and file integrity.

### Milestone 4 (Perf Tier + GitHub Action)
- Add 4 performance rules.
- Publish GitHub Action.
- Complete documentation.
- Performance benchmarking.

---

## 3. Gates

- **Gate 0**: Pipeline tests pass.
- **Gate 1**: Zero false positives in correctness tier.
- **Gate 2**: Config parser and style tier tested.
- **Gate 3**: OLS integration and auto-fix validated.
- **Gate 4**: Full test suite passes, documentation complete.

---

## 4. Testing

- Fixture-based testing for rules.
- Snapshot testing for diagnostic output.
- Integration tests for OLS and GitHub Action.
- Performance benchmarking on Odin stdlib.

---

## 5. Logging

- Guard logging output with `when` statements to avoid clutter.

---

## 6. Build System

- Use `build.odin` in the `build` folder for compilation.
- Executables output to `artifacts`.

---

## 7. Scripts

- Place utility scripts in the `scripts` folder.
