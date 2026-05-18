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
olt setup        # OLS detection → install → MCP registration (3-step wizard)
```

### Build from source

Requires Odin `dev-2026-05` or newer.
```bash
git clone --recurse-submodules https://github.com/RainerXE/odintooling
cd odintooling
./scripts/build.sh        # → artifacts/macos-arm64/olt
```

### First-run setup

```bash
olt setup        # full system setup — runs the 3-step wizard below
olt init         # create olt.toml in a project directory
```

`olt setup` is a 3-step wizard:

**Step 1 — OLS** — detects [OLS](https://github.com/DanielGavin/ols) in `PATH` (both `ols` and `ols_lsp` / Homebrew). Lets you confirm or override the path.

**Step 2 — Install** — copies `olt` to `~/.local/bin/` and creates three symlinks that enable argv[0] dispatch:
- `ols → olt` — point your editor here instead of vanilla OLS
- `olt-lsp → olt` — backward-compat LSP name
- `olt-mcp → olt` — backward-compat MCP name

**Step 3 — MCP** — detects installed AI coding tools and registers `olt-mcp` in each one's config file automatically. Supports:

| Tool | Config file written |
|------|-------------------|
| Claude Code | `claude mcp add` (CLI) |
| Cursor | `~/.cursor/mcp.json` |
| Cline | `…/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` |
| Codex | `~/.codex/config.toml` |
| OpenCode | `~/.config/opencode/opencode.json` |
| Antigravity | `~/.gemini/antigravity/mcp_config.json` |
| Hermes Agent | `~/.hermes/config.yaml` |

Config paths resolve correctly on macOS, Linux, and Windows. If a tool's config directory isn't at the expected location, the wizard asks for it.

`olt init` checks whether setup has been run and offers to run it first if needed.

---

## Usage

```bash
olt src/                      # lint a directory (recursive)
olt file.odin                 # lint a single file
olt src/ --fix                # apply safe auto-fixes in-place
olt src/ --format json        # machine-readable output (json or sarif)
olt src/ --rule C001,C201     # run specific rules only
olt src/ --tier correctness   # run only correctness-tier rules
olt --explain C001            # detailed rule documentation
olt --list-rules              # show all available rules

olt mcp                       # start MCP server (AI agent interface)
olt lsp                       # start LSP proxy (editor interface)
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

Run `olt init` in your project directory to generate one, or create it manually:

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
ols_path = "/usr/local/bin/ols_lsp"   # path to OLS (if not in PATH)
```

### Inline suppression

```odin
buf := make([]u8, n)  // olt:ignore C001 arena-managed, freed by caller
```

Multiple rules: `// olt:ignore C001,C002`

Legacy alias `// odin-lint:ignore` is also accepted.

---

## Editor integration

`olt lsp` is an LSP proxy: your editor talks to it as the single Odin language server.
It forwards everything to vanilla [OLS](https://github.com/DanielGavin/ols) (completions, hover, go-to-definition) and injects olt diagnostics into the diagnostic stream.

After `olt setup`, an `ols` symlink is created pointing to `olt`. Point your editor at that symlink — no other changes needed.

**VS Code** (`settings.json`):
```json
"odin.languageServer.path": "/path/to/ols"
```

**Helix** (`languages.toml`):
```toml
[[language]]
name = "odin"
language-servers = ["ols"]

[language-server.ols]
command = "/path/to/ols"
```

**Neovim** (lspconfig):
```lua
require('lspconfig').ols.setup { cmd = { '/path/to/ols' } }
```

OLS must be installed separately: [github.com/DanielGavin/ols](https://github.com/DanielGavin/ols).
Homebrew installs it as `ols_lsp` — `olt setup` detects both names automatically.

---

## AI agent integration

`olt mcp` exposes olt as an [MCP](https://modelcontextprotocol.io) server for Claude Code and other AI agents.

`olt setup` registers `olt-mcp` automatically for every detected tool (see [First-run setup](#first-run-setup)).

For manual registration, add to your tool's MCP config file — the binary is `~/.local/bin/olt-mcp` after setup:

```json
{
  "mcpServers": {
    "olt-mcp": { "command": "/Users/you/.local/bin/olt-mcp", "args": [] }
  }
}
```

Codex (`~/.codex/config.toml`):
```toml
[mcp_servers.olt_mcp]
command = "/Users/you/.local/bin/olt-mcp"
enabled = true
```

Hermes Agent (`~/.hermes/config.yaml`):
```yaml
mcp_servers:
  olt-mcp:
    command: /Users/you/.local/bin/olt-mcp
    args: []
```

Available MCP tools:

| Tool | Description |
|------|-------------|
| `lint_file` | Lint a file on disk |
| `lint_snippet` | Lint in-memory source text |
| `lint_fix` | Return proposed fixes as JSON |
| `lint_workspace` | Batch-lint a directory |
| `list_rules` | Return the full rule catalog as JSON |
| `run_odin_check` | Run `odin check` and return compiler diagnostics |
| `get_symbol` | Look up a symbol in the code graph |
| `export_symbols` | Build the code knowledge graph |
| `get_dna_context` | Callers, callees, memory role for a proc |
| `get_impact_radius` | Transitive impact of changing a symbol |
| `get_callers` / `get_callees` | Direct call graph neighbours |
| `search_symbols` | Full-text symbol search |
| `rename_symbol` | Generate rename patches across the project |

### Code knowledge graph

Build a semantic graph of your project for deeper analysis:

```bash
olt src/ --export-symbols
```

By default this writes to `.codegraph/odin_lint_graph.db` and `.codegraph/symbols.json`. Pass a custom path via `--db=<path>` or the MCP `export_symbols` tool.

Add `.codegraph/` to your `.gitignore` to keep generated graph files out of version control:
```
.codegraph/
```

Once exported, this enables:
- C202 switch exhaustiveness checking
- All `get_*` / `search_symbols` MCP tools for AI-assisted refactoring

### CodeGraph integration

[CodeGraph](https://github.com/colbymchenry/codegraph) is a code intelligence MCP server that gives AI agents fast symbol search, call graphs, and impact analysis across 19+ languages. olt can write a CodeGraph-compatible database so Odin projects work with it too.

**First-time setup** (run once per project):

```bash
olt --codegraph-init src/
```

This does a full index and writes `.codegraph/codegraph.db` in the schema CodeGraph expects. It also writes `.codegraph/.gitignore` so the database is not committed. No `codegraph init` needed — olt handles everything.

**Keeping it updated** (run after code changes):

```bash
olt --codegraph-sync src/
```

Incremental — only re-indexes changed files. Prints a clear error if `--codegraph-init` has not been run yet.

Once the database is in place, all CodeGraph MCP tools work on your Odin codebase:

| Tool | What it does |
|------|-------------|
| `codegraph_search` | Find symbols by name |
| `codegraph_context` | Get code context relevant to a task |
| `codegraph_callers` | What calls a function |
| `codegraph_callees` | What a function calls |
| `codegraph_impact` | Transitive impact of changing a symbol |
| `codegraph_node` | Full details + source for a symbol |

> **Note**: Do not run `codegraph init` on an Odin project. CodeGraph does not support Odin and will hang trying to pre-load its WASM grammars. `olt --codegraph-init` is the correct entry point.

---

## Architecture

```
                ┌─────────────────────────────┐
                │           olt               │
                │  argv[0] / subcommand       │
                │  dispatch                   │
                └──────┬──────────┬───────────┘
                       │          │
              ┌────────┴──┐  ┌────┴──────┐
              │  olt lsp  │  │  olt mcp  │
              │  (editor) │  │  (agent)  │
              └────────┬──┘  └───────────┘
                       │
                  shared rule engine
                  analyze_content()
                       │
                  C001–C203 rules
```

Symlinks created by `olt setup`:
- `ols → olt` — IDE OLS integration (argv[0] dispatch → LSP mode)
- `olt-lsp → olt` — backward compat
- `olt-mcp → olt` — backward compat

---

## Project layout

```
src/main.odin      Unified entry point (argv[0] + subcommand dispatch)
src/core/          Rule engine, CLI, config parsing, graph DB
src/mcp/           MCP server tools
src/lsp/           LSP proxy
ffi/tree_sitter/   Tree-sitter grammar + static libraries
ffi/sqlite/        SQLite static library
vendor/odin-mcp    MCP protocol library (https://github.com/RainerXE/odin-mcp)
tests/             Rule test fixtures
scripts/           Build and test scripts
```

---

## Contributing

Run the full test suite before submitting:

```bash
./scripts/run_c001_tests.sh
./scripts/run_c002_tests.sh
# ... see scripts/run_*.sh for all rule suites
./artifacts/macos-arm64/olt src/   # must produce 0 violations
```

---

## License

[MIT](https://en.wikipedia.org/wiki/MIT_License)

> "The miracle is this: The more we share the more we have." — Leonard Nimoy
