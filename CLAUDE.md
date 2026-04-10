# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`odin-lint` is a Clippy-inspired static analyzer for the Odin programming language. It detects correctness issues (memory leaks, double-frees) and style violations (naming conventions, visibility markers). The codebase is written in Odin and links against tree-sitter C libraries for AST parsing.

## Build Commands

```bash
# Build main executable → artifacts/odin-lint
./scripts/build.sh

# Build OLS plugin (macOS dylib) → artifacts/odin-lint-plugin.dylib
./scripts/build_plugin.sh

# Rebuild tree-sitter static libraries (rarely needed, pre-built binaries exist)
./scripts/build_external_tree_sitter.sh
```

## Running Tests

```bash
# Run C001 (memory allocation) tests
./scripts/run_c001_tests.sh
./scripts/test_all_c001_tests.sh

# Run C002 (double-free) tests
./scripts/run_c002_tests.sh
./scripts/test_all_c002_tests.sh

# Test against real-world codebases
./scripts/test_ruishin.sh        # RuiShin codebase
./scripts/test_vendor_ols.sh     # OLS codebase
./scripts/test_our_codebase.sh   # This codebase (should produce 0 violations)

# Full suite
./scripts/comprehensive_odin_test.sh
```

Test fixtures are in `tests/C001_COR_MEMORY/` and `tests/C002_COR_POINTER/` as `.odin` files with expected violation counts.

## Architecture

### Dual Analysis Paths

There are two separate analysis pipelines:

1. **CLI path** (`src/core/`) — Uses tree-sitter for file-based batch linting. Entry point: `main.odin`. Invoked as `./artifacts/odin-lint <file.odin>`.

2. **OLS plugin path** (`src/core/plugin_main.odin`, `odin_lint_plugin.odin`) — Receives `^ast.File` from the Odin Language Server for real-time editor diagnostics. Builds to `artifacts/odin-lint-plugin.dylib`.

### Rule Organization

Rules live in `src/core/` as individual files:

| File | Rule | Category |
|------|------|----------|
| `c001-COR-Memory.odin` | C001 | Memory allocation without free |
| `c002-COR-Pointer.odin` | C002 | Double-free detection |
| `c003-STY-Naming.odin` | C003 | Proc names must be `snake_case` |
| `c004-STY-Private.odin` | C004 | Private proc visibility |
| `c005-STY-Internal.odin` | C005 | Internal proc visibility |
| `c006-STY-Public.odin` | C006 | Public API doc comments |
| `c007-STY-Types.odin` | C007 | Type names must be `PascalCase` |
| `c008-STY-Acronyms.odin` | C008 | Acronym identifier handling |

Each rule exports an `analyze_*` proc that takes file content/lines and returns `[]Diagnostic`.

### Tree-Sitter FFI

- `tree_sitter_bindings.odin` — Raw `foreign` bindings to `libtree-sitter.a` and `libtree-sitter-odin.a`
- `tree_sitter.odin` — High-level Odin wrappers (`initTreeSitter`, `parseFile`, node traversal helpers)
- Static libraries live in `ffi/tree_sitter/tree-sitter-lib/` (pre-compiled, checked in)

### Suppression System

`suppression.odin` parses inline comments to suppress specific rules:
```odin
buf := make([]u8, 100)  // odin-lint:ignore=C001
```

### Configuration

`odin-lint.toml` controls rule severity (error/warn/disabled), path exclusions (vendor/, core/), and performance thresholds. The `ols.json` registers the plugin with OLS per platform.

## Key Development Patterns

**Diagnostic emission** uses a `DiagnosticType` enum (`VIOLATION`, `CONTEXTUAL`, `INTERNAL_ERROR`, `INFO`) and is handled centrally in `main.odin`.

**Scope tracking** in correctness rules (C001, C002) uses explicit scope stacks with `start_line`-based matching — not string matching — to avoid false positives.

**File reading** is done once per analysis pass and the `lines` slice is passed through recursive calls. Never re-read files during analysis.

**Word boundary checks** are required when searching for variable names in text to prevent partial-match false positives.

## Implementation Plans

The `plans/` directory contains detailed implementation roadmaps. The current plan is `plans/odin-lint-implementation-planV7.md`. Check this before starting work on new rules or architectural changes — it contains lessons learned, milestone gates, and the Query Engine (SCM) design for M3.1.
