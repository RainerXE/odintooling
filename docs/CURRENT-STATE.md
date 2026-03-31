# Current State of Odin-Lint

## Summary

This document summarizes the current state of the `odin-lint` project and outlines the next steps.

## What Works

✅ **Odin-lint compiles and runs** (with placeholder tree-sitter).
✅ **Tree-sitter libraries are built** (`libtree-sitter.a`, `libtree-sitter-odin.a`).
✅ **OLS integration is minimal and non-intrusive**.
✅ **CLI mode is functional** (with placeholder AST).

## What’s Missing

❌ **Real tree-sitter FFI** (requires research).
❌ **C001/C002 rules** (operate on placeholder AST).
❌ **Plugin mode** (not wired into OLS yet).

## Files

### Core
- `src/core/main.odin`: CLI entry point.
- `src/core/tree_sitter.odin`: Placeholder tree-sitter (needs real FFI).
- `src/core/tree_sitter_real.odin`: Real FFI (WIP).

### OLS Integration
- `vendor/ols/src/server/plugin.odin`: Plugin interface.
- `vendor/ols/src/server/plugin_manager.odin`: Plugin lifecycle.
- `vendor/ols/src/server/plugin_dynamic.odin`: Dynamic loading.

### Build
- `build_tree_sitter.sh`: Script to build tree-sitter libraries.
- `build.sh`: Main build script.

### Documentation
- `docs/TREE-SITTER-IMPLEMENTATION.md`: Guide for real FFI.
- `docs/TREE-SITTER-FFI.md`: FFI analysis.
- `docs/CURRENT-STATE.md`: This file.

## Next Steps

### High Priority
1. **Implement real tree-sitter FFI** (using `odin-c-bindgen` or manual `foreign`).
2. **Test with real Odin files** (e.g., `test/error.odin`).
3. **Add C001/C002 rules** (real AST analysis).

### Medium Priority
1. **Wire plugin mode** into OLS.
2. **Add more rules** (C003–C008).
3. **Improve error reporting** (e.g., JSON output).

### Low Priority
1. **Add `--ast=json` flag** for AI tools.
2. **Add `--fix` flag** for automatic fixes.
3. **Add `--config` flag** for rule configuration.

## How to Help

1. **Test the CLI**: Run `odin-lint` on real Odin files.
2. **Report issues**: Open GitHub issues for bugs.
3. **Contribute code**: Submit PRs for features.

## Questions

- **Why is tree-sitter a placeholder?**
  - Odin’s FFI is complex and requires research.
  - We’re using a placeholder to unblock development.

- **How do I test the CLI?**
  - Run `./odin-lint test/error.odin`.
  - Expect "Failed to initialize tree-sitter parser" (placeholder).

- **How do I build the project?**
  - Run `./build.sh`.
  - Output: `odin-lint` binary.

## Links

- [Odin](https://odin-lang.org/)
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)
- [OLS](https://github.com/ols/ols)
