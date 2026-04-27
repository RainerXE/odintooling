# olt — Odin Language Tools

A [Clippy](https://github.com/rust-lang/rust-clippy)-inspired static analyser for the [Odin programming language](https://odin-lang.org).
Catches memory leaks, double-frees, naming violations, unchecked errors, and more — before the compiler or runtime does.

```
$ olt src/
🔴 src/core/main.odin:42:5: C001 [correctness] Allocation without matching defer free
Fix: Add 'defer delete(buf)' immediately after the allocation
🔴 src/api/handlers.odin:18:9: C201 [correctness] error return of 'os.open' is discarded
1 violation(s) in 2 file(s)
```

---

## Install

### Pre-built binaries

Download from [Releases](https://github.com/RainerXE/odintooling/releases) for your platform, then:

```bash
./olt --install       # installs to ~/.local/bin/
```

### Build from source

Requires Odin `dev-2026-04` or newer.

```bash
git clone --recurse-submodules https://github.com/RainerXE/odintooling
cd odintooling
./scripts/build.sh        # → artifacts/macos-arm64/olt
./scripts/build_mcp.sh    # → artifacts/macos-arm64/olt-mcp  (AI agent interface)
./scripts/build_lsp.sh    # → artifacts/macos-arm64/olt-lsp  (editor interface)
```

### First-run setup

```bash
olt --init
```

Detects OLS, creates `olt.toml` with a rule profile, and installs binaries to `~/.local/bin/`.

---

## Usage

```bash
olt src/                      # lint a directory (recursive)
olt file.odin                 # lint a single file
olt src/ --fix                # apply safe auto-fixes in-place
olt src/ --propose            # show proposed fixes as a diff
olt src/ --format json        # machine-readable output (json or sarif)
olt src/ --rule C001,C201     # run specific rules only
olt src/ --tier correctness   # run only correctness-tier rules
olt --explain C001            # detailed rule documentation
olt --list-rules              # show all available rules
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | No violations |
| `1` | One or more violations |
| `2` | Usage error or internal failure |

---

## Rules

### Correctness

| Rule | What it catches |
|------|----------------|
| C001 | Heap allocation (`make`/`new`) without `defer delete`/`defer free` |
| C002 | Double-free or use-after-free |
| C009 | Deprecated `core:os/old` import — use `core:os` |
| C010 | `Small_Array` superseded by `[dynamic; N]T` |
| C011 | FFI C resource (`ts_*_new`) without matching `defer ts_*_delete` |
| C101 | `context.allocator` reassigned without defer restore |
| C201 | Error return value discarded (unchecked result) |
| C202 | Switch on enum not exhaustive (requires `--export-symbols`) |
| C203 | `defer` in inner block fires before outer scope uses the handle |

### Style

| Rule | What it catches |
|------|----------------|
| C003 | Procedure names must be `snake_case` |
| C007 | Type/struct/enum names must be `PascalCase` |
| C016 | Local variable names must be `snake_case` (default on) |
| C031 | `panic()` on expected runtime failure — consider error return (INFO) |
| C034 | `for v, _ in collection` — blank index unnecessary (INFO, auto-fix) |
| C037 | Trailing `return` at end of void procedure (INFO, auto-fix) |

### Opt-in domains

Enable in `olt.toml`:

| Domain | Rules | What it enables |
|--------|-------|----------------|
| `stdlib_safety = true` | C029, C033 | `strings.split/clone/join`, `fmt.aprintf`, `os.read_entire_file` without `defer delete`; `strings.builder_make` without `defer strings.builder_destroy` |
| `go_migration = true` | C021–C023, C025 | Go-style `fmt.Println`, `for i,v := range`, `*ptr` deref, `append(s,v)` without `&` |
| `semantic_naming = true` | C012 | Ownership naming hints (`_ptr`, `_owned`, etc.) |
| `dead_code = true` | C014, C015 | Unexported procedures and constants never referenced |
| `ffi = true` | C011 | FFI resource safety (auto-detected if `ffi/` directory exists) |

---

## Configuration — olt.toml

Place `olt.toml` at your project root (or run `olt --init` to generate one):

```toml
[domains]
ffi           = true   # C011: FFI resource safety
odin_2026     = true   # C009/C010: deprecated API detection
stdlib_safety = true   # C029/C033: stdlib allocation safety

[naming]
c016 = true   # local variables must be snake_case
c019 = false  # type marker suffixes (opt-in)
c020 = false  # minimum name length (opt-in)
c020_min_length = 3
c020_allowed    = "i,j,k,x,y,z,n,ok,err,db,id"

[tools]
ols_path = "/usr/local/bin/ols"   # path to OLS (if not in PATH)
```

### Inline suppression

```odin
buf := make([]u8, n)  // olt:ignore C001 arena-managed, freed by caller
```

Multiple rules: `// olt:ignore C001,C002`

Legacy alias `// odin-lint:ignore` is also accepted.

---

## Editor integration — olt-lsp

`olt-lsp` is an LSP proxy: your editor talks to it as the single Odin language server.
It forwards everything to vanilla [OLS](https://github.com/DanielGavin/ols) (completions, hover, go-to-definition) and injects olt lint diagnostics into the diagnostic stream.

**VS Code** (`settings.json`):
```json
"odin.languageServer.path": "/path/to/olt-lsp"
```

**Helix** (`languages.toml`):
```toml
[[language]]
name = "odin"
language-servers = ["olt-lsp"]

[language-server.olt-lsp]
command = "/path/to/olt-lsp"
```

**Neovim** (lspconfig):
```lua
require('lspconfig').ols.setup { cmd = { '/path/to/olt-lsp' } }
```

OLS must be installed separately: [github.com/DanielGavin/ols](https://github.com/DanielGavin/ols).
Configure its path in `olt.toml` under `[tools] ols_path` or let olt find it via PATH.

---

## AI agent integration — olt-mcp

`olt-mcp` exposes olt as an [MCP](https://modelcontextprotocol.io) server for Claude Code and other AI agents.

Register in `~/.claude/mcp_servers.json`:
```json
{
  "mcpServers": {
    "olt": { "command": "/path/to/olt-mcp", "args": [] }
  }
}
```

Available MCP tools:

| Tool | Description |
|------|-------------|
| `lint_file` | Lint a file on disk |
| `lint_snippet` | Lint in-memory source text |
| `lint_fix` | Apply fixes and return a before/after diff |
| `lint_workspace` | Batch-lint a directory |
| `list_rules` | Return the full rule catalog as JSON |
| `run_odin_check` | Run `odin check` and return compiler diagnostics |
| `codegraph_search` | Search the code knowledge graph by symbol name |
| `codegraph_context` | Get relevant context for a task |
| `codegraph_callers` | Find what calls a function |
| `codegraph_callees` | Find what a function calls |
| `codegraph_impact` | See what's affected by changing a symbol |
| `codegraph_node` | Get source and metadata for a symbol |

### Code knowledge graph

Build a semantic graph of your project for deeper analysis:

```bash
olt src/ --export-symbols
```

This writes a SQLite database to `.codegraph/olt_graph.db` and enables:
- C202 switch exhaustiveness checking
- `codegraph_*` MCP tools for AI-assisted refactoring
- C012 T3 graph-backed ownership analysis

---

## Architecture

```
                ┌─────────────┐
  $ olt src/    │  olt (CLI)  │  analyze_file → rule pipeline
                └─────────────┘
                       │
               shared rule engine
               analyze_content()
                       │
         ┌─────────────┼──────────────┐
         │             │              │
  ┌──────────┐  ┌──────────┐  ┌────────────┐
  │  olt-lsp │  │ olt-mcp  │  │ rule files │
  │ (editor) │  │  (agent) │  │ C001–C203  │
  └──────────┘  └──────────┘  └────────────┘
       │
  [OLS proxy]
  Forwards to vanilla OLS, injects lint diagnostics
```

---

## Project layout

```
src/core/          Rule engine, CLI, config parsing, graph DB
src/mcp/           MCP server tools
src/lsp/           LSP proxy (olt-lsp)
ffi/tree_sitter/   Tree-sitter grammar + static libraries
ffi/sqlite/        SQLite static library
vendor/odin-mcp    MCP protocol library (https://github.com/RainerXE/odin-mcp)
vendor/odin-sqlite3 SQLite Odin bindings
tests/             Rule test fixtures
scripts/           Build and test scripts
```

---

## Contributing

Run the full test suite before submitting:

```bash
./scripts/run_c001_tests.sh
./scripts/run_c002_tests.sh
./scripts/run_c029_c033_tests.sh
# ... see scripts/run_*.sh for all rule suites
./artifacts/macos-arm64/olt src/   # must produce 0 violations
```

---

## License

MIT
