# olt — Odin Language Tools

**A code graph and static analyser built for [Odin](https://odin-lang.org).**
olt indexes your project into a SQLite graph, serves it to AI coding agents over MCP, and lints it with
[Clippy](https://github.com/rust-lang/rust-clippy)-style rules — memory leaks, double-frees, unchecked errors, naming — using
what only an Odin-aware tool knows: a package is a directory, who allocates and who frees, what `defer` pairs with.

It is an Odin-specific **alternative to [CodeGraph](https://github.com/colbymchenry/codegraph)**, and a compatible one:
olt's graph database *is* a CodeGraph database (see [olt and CodeGraph](#olt-and-codegraph)).

```
$ olt src/
🔴 src/core/main.odin:42:5: C001 [correctness] Allocation without matching defer free
Fix: Add 'defer delete(buf)' immediately after the allocation
🔴 src/api/handlers.odin:18:9: C201 [correctness] error return of 'os.open' is discarded
1 violation(s) in 2 file(s)
```

---

## olt and CodeGraph

[CodeGraph](https://github.com/colbymchenry/codegraph) is a general code-intelligence MCP server for many languages. olt does
the same job for one language, and adds what that language lets a tool know.

| | olt | CodeGraph |
|---|---|---|
| Languages | Odin | many |
| Database | `.codegraph/olt.db` — CodeGraph's own schema (v16, vendored unmodified) plus olt tables | `.codegraph/codegraph.db` |
| Odin specifics | a bare call resolves only inside its package (a directory); `pkg.fn()` resolves through the file's imports (alias, declared package name, relative path, `src:`-style collections); memory role per procedure (allocator / deallocator / borrower); lint findings attached to the procedure they are in; enum exhaustiveness; FFI resource-safety checks; opt-in dead-code detection | general extraction — Odin support has been proposed upstream ([#3091](https://github.com/colbymchenry/codegraph/pull/3091)) |
| Also does | linting (22 rules, `--list-rules`), `--fix`, an LSP proxy that merges olt diagnostics into OLS, `rename_symbol`, `run_odin_check` | `explore`/`node`/`context` tools, agent hooks, live file watching |
| Runtime | one native binary, no Node | Node 22.5+ (the installers bundle it) |

**How close is the graph?** Measured against the Odin index that the CodeGraph proposal above produces, on the same
checkouts, olt has 95% of its distinct call edges on [odin-http](https://github.com/laytan/odin-http) and 96% on
[ols](https://github.com/DanielGavin/ols) (cross-package calls included). That compares edges, not agent answers: whether either graph
makes an agent faster is not something this README claims.

**Which to use.** Odin-only project, or you want linting and ownership-aware answers from the same index: olt. A repository that
mixes languages, or you want CodeGraph's explore tools and viewer: CodeGraph. Both is fine, because they speak the same schema:
`olt --codegraph-init .` writes the database where CodeGraph looks for it, for a CodeGraph that does not index Odin itself yet.

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

This writes `.codegraph/olt.db` and `.codegraph/symbols.json`; pass another path with `--db=<path>` or the MCP `export_symbols` tool.
Add `.codegraph/` to your `.gitignore` to keep generated files out of version control.

The database is a [CodeGraph](https://github.com/colbymchenry/codegraph) database. Its core tables come from CodeGraph's schema,
vendored unmodified in `ffi/codegraph/` (refresh with `scripts/update_codegraph_schema.sh`):

- **nodes** — `file`, `function`, `struct`, `union`, `enum`, `enum_member`, `constant`, `variable` and `import`, each with its
  start and end position, signature, return type and visibility; qualified names are `package::name`
- **edges** — `contains` (file → declaration, enum → member) and `calls`
- **unresolved_refs** — calls whose target is outside the project (`fmt::println`) or is a value (`a.b.f`)
- **files**, **nodes_fts** (full-text search), **project_metadata**, **schema_versions**

olt's own data lives beside them in `odin_*` tables, which CodeGraph never touches: `odin_node_info` (memory role and lint
findings per node), `odin_package` (the package each file declares) and `odin_import` (what each file's qualifiers refer to).

Once exported, this enables C202 switch exhaustiveness checking and the `get_*` / `search_symbols` MCP tools.

### CodeGraph integration

Because the graph is a CodeGraph database, CodeGraph's tools can read it. If your CodeGraph does not index Odin itself (it skips
`.odin` files; Odin support is proposed in [colbymchenry/codegraph#3091](https://github.com/colbymchenry/codegraph/pull/3091)),
let olt write the database it reads:

```bash
olt --codegraph-init .        # full index into .codegraph/codegraph.db
olt --codegraph-sync .        # after code changes: incremental
```

A target directory is required. This is the ordinary export, written to `.codegraph/codegraph.db` (plus a `.gitignore` there), so
`codegraph status`, `codegraph callers`, `codegraph query` and the MCP tools work on your Odin code.

**One writer per database.** Once your CodeGraph indexes Odin, let it own `codegraph.db` and keep olt's graph in
`.codegraph/olt.db` (`olt --export-symbols`). A CodeGraph reindex rewrites the nodes, which drops olt's `odin_*` rows; olt adds
them back on its next run.

The compatibility is tested, not assumed: `scripts/test_codegraph_contract.sh` builds a graph with olt and drives a real CodeGraph
over it (status, queries, and the `sync` that used to fail with `duplicate column name`). Run it against the CodeGraph you target:

```bash
CODEGRAPH_BIN="codegraph" ./scripts/test_codegraph_contract.sh
```

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

## Changelog

### 0.97.3 (2026-07-10)
- Fix installer issues: binary now properly installs to target directory
- Fix MCP configuration corruption issues
- Add backup/restore for existing configurations
- Improve error handling in installation process

## License

[MIT](https://en.wikipedia.org/wiki/MIT_License)

> "The miracle is this: The more we share the more we have." — Leonard Nimoy
