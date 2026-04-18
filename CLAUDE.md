# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`odin-lint` is a Clippy-inspired static analyzer for the Odin programming language. It detects correctness issues (memory leaks, double-frees) and style violations (naming conventions, visibility markers). Written in pure Odin, links against tree-sitter C libraries for AST parsing.

## Build Commands

```bash
# Build main CLI executable → artifacts/odin-lint
./scripts/build.sh

# Build OLS plugin (macOS dylib) → artifacts/odin-lint-plugin.dylib
./scripts/build_plugin.sh

# Build MCP server → artifacts/odin-lint-mcp
./scripts/build_mcp.sh

# Rebuild tree-sitter static libraries (rarely needed, pre-built binaries checked in)
./scripts/build_external_tree_sitter.sh
```

## Running Tests

```bash
# Rule-specific test suites
./scripts/run_c001_tests.sh
./scripts/run_c002_tests.sh

# Regression: this codebase must produce 0 violations
./scripts/test_our_codebase.sh

# Real-world codebase tests
./scripts/test_ruishin.sh
./scripts/test_vendor_ols.sh
```

Test fixtures are in `tests/C001_COR_MEMORY/` and `tests/C002_COR_POINTER/`.

## Architecture

### Three Analysis Surfaces

All three surfaces share the same rule implementations via `src/core/analyze_content.odin`:

1. **CLI** (`src/core/main.odin`) — file-based batch linting. `./artifacts/odin-lint <file.odin>`

2. **OLS plugin** (`src/core/plugin_main.odin`) — real-time editor diagnostics via the OLS Language Server plugin interface. Exports `ols_plugin_get :: proc "c" ()`. Built as `artifacts/odin-lint-plugin.dylib`. Registered in `ols.json`. OLS plugin system lives in `vendor/ols/src/server/plugin.odin`.

3. **MCP server** (`src/mcp/`) — exposes lint tools to Claude Code and other MCP clients over stdio JSON-RPC. Built as `artifacts/odin-lint-mcp`. Uses `vendor/odin-mcp/` as the protocol library.

### Shared In-Memory Analysis Entry Point

`src/core/analyze_content.odin` — `analyze_content(file_path, content, ts_parser, diags)` runs all rules (C001–C011) on in-memory source text. Both the OLS plugin and the MCP `lint_snippet` tool call this. The CLI `analyze_file` reads from disk then calls this same pipeline.

### Rule Organization

Rules live in `src/core/` as individual files. Current rules:

| File | Rule | Method |
|------|------|--------|
| `c001-COR-Memory.odin` | C001 — allocation without defer free | AST walker |
| `c002-COR-Pointer.odin` | C002 — double-free detection | SCM query |
| `c003-STY-Naming.odin` | C003+C007 — proc/type naming conventions | SCM query |
| `c009-MIG-OsOld.odin` | C009 — deprecated `core:os/old` imports | SCM query |
| `c010-MIG-Fmt.odin` | C010 — deprecated fmt procs | SCM query |
| `c011-FFI-Safety.odin` | C011 — FFI resource leak (ts_*_new without defer) | SCM query |
| `c012-SEM-Naming.odin` | C012 — semantic ownership naming | deferred to M6 |

Rules C003 and C007 share a single SCM pass (`naming_scm_run` in `c003-STY-Naming.odin`). C009 and C010 share a single SCM pass too.

### SCM Query Engine

`src/core/query_engine.odin` — `CompiledQuery`, `load_query_src`, `run_query`, `free_query_results`. SCM (S-expression) query files are embedded at compile time via `#load` in `src/core/scm_queries.odin`. The tree-sitter parser is initialised once and reused across all rule passes.

### Tree-Sitter FFI

- `src/core/tree_sitter_bindings.odin` — raw `foreign` bindings to `libtree-sitter.a` and `libtree-sitter-odin.a`
- `src/core/tree_sitter.odin` — high-level wrappers (`initTreeSitterParser`, `parseToAST`, node helpers)
- Static libraries: `ffi/tree_sitter/tree-sitter-lib/` and `ffi/tree_sitter/tree-sitter-odin/`

### MCP Protocol Library

`vendor/odin-mcp/` — standalone, reusable Odin MCP library. **No dependency on odin-lint.** Any Odin project can import this to build an MCP server without implementing the protocol from scratch.

- `types.odin` — `MCPServer`, `RegisteredTool`, `ToolHandler`, `RPCID`
- `transport.odin` — Content-Length framing (identical to LSP)
- `json_helpers.odin` — response builders
- `server.odin` — `server_init`, `server_register_tool`, `server_run` dispatch loop

MCP tools in `src/mcp/`: `lint_file`, `lint_snippet`, `lint_fix` (real); `get_symbol`, `export_symbols` (stubs, M5.6).

### OLS Fork

`vendor/ols/` — fork of DanielGavin/ols with our plugin system added. Key additions:
- `src/server/plugin.odin` — C-ABI plugin interface, registry, `plugin_run_diagnostics`
- `src/server/types.odin` — `source` field added to `Diagnostic` struct
- `src/server/config.odin` — `PluginConfig`, `plugins` slice in `Config`
- `requests.odin`, `action.odin`, `main.odin` — plugin hooks wired in

Build the OLS binary: `cd vendor/ols && ./build.sh` → `vendor/ols/ols`.
Install: copy `vendor/ols/ols` to wherever your editor expects it (e.g. `artifacts/ols`).

### Suppression System

`src/core/suppression.odin` — inline comment suppression:
```odin
buf := make([]u8, 100)  // odin-lint:ignore C001
```

### Configuration

`odin-lint.toml` — rule severity, path exclusions, performance thresholds.
`ols.json` — OLS workspace config including plugin registration.

## Key Development Patterns

**In-memory analysis** — `analyze_content` is the canonical entry point for all surfaces except the batch CLI. Never duplicate the rule-running loop; always call `analyze_content`.

**Tree-sitter parser lifetime** — initialised once at startup (`initTreeSitterParser`), reused across all calls. Never re-initialise per file. The pattern is a file-scope `_ts_parser` variable in each entry point (`main.odin`, `plugin_main.odin`, `src/mcp/main.odin`).

**Scope tracking** in C001/C002 uses `start_line`-based matching, not string matching — avoids false positives from same-named variables in different scopes.

**File reading** — done once per analysis pass; the `lines []string` slice is passed through all recursive calls. Never re-read files during analysis.

**Memory in the OLS plugin** — all result memory is heap-allocated (`runtime.heap_allocator()`). OLS calls `free_result` when done. Never use temp or context allocator for plugin results.

**MCP request memory** — each request uses `context.temp_allocator`; `free_all(context.temp_allocator)` runs at the end of every server loop iteration.

## Implementation Plans

`plans/odin-lint-implementation-planV7.md` is the authoritative roadmap. Check it before starting new rules or architectural changes. Current milestone status:

- M0–M4.5: ✅ Complete
- M5 OLS Plugin: ✅ Complete (April 18 2026)
- M5.5 MCP Gateway: ✅ Complete (April 18 2026)
- M5.6 DNA Impact Analysis + Call Hierarchy: ⬜ Next
- M6 Extended Rules (C012 type-gated): ⬜ Planned
