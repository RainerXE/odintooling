# olt — Odin Language Tools

**A code graph and static analyser built for [Odin](https://odin-lang.org).**
olt indexes your project into a SQLite graph, serves it to AI coding agents over MCP, and lints it with
[Clippy](https://github.com/rust-lang/rust-clippy)-style rules — memory leaks, double-frees, unchecked errors, naming — using
what only an Odin-aware tool knows: a package is a directory, who allocates and who frees, what `defer` pairs with.

It is an Odin-specific **alternative to [CodeGraph](https://github.com/colbymchenry/codegraph)**, and a compatible one:
olt's graph database *is* a CodeGraph database (see [olt and CodeGraph](#olt-and-codegraph)).

```
$ olt src/
🔴 /work/app/src/config.odin:6:2: C001 [correctness] Allocation without matching defer free in same scope
Fix: Add 'defer free()' or 'defer delete()' immediately after this allocation
🔴 /work/app/src/config.odin:8:5: C201 [correctness] error return of 'os.close' is discarded
Fix: Assign the result and handle the error, or use 'or_return'
2 violation(s) in 1 file(s)
```

---

## olt and CodeGraph

[CodeGraph](https://github.com/colbymchenry/codegraph) is a general code-intelligence MCP server for many languages. olt does
the same job for one language, and adds what that language lets a tool know.

| | olt | CodeGraph |
|---|---|---|
| Languages | Odin | many |
| Database | `.codegraph/olt.db` — CodeGraph's own schema (v16, vendored unmodified) plus olt tables | `.codegraph/codegraph.db` |
| Odin specifics | a bare call resolves only inside its package (a directory); `pkg.fn()` resolves through the file's imports (alias, declared package name, relative path, `src:`-style collections); who owns each allocation (which allocator, freed / returned / stored / passed on, factories, leak candidates — see [Memory ownership](#memory-ownership)); memory role per procedure (allocator / deallocator / borrower); lint findings attached to the procedure they are in; enum exhaustiveness; FFI resource-safety checks; opt-in dead-code detection | general extraction — Odin support has been proposed upstream ([#3091](https://github.com/colbymchenry/codegraph/pull/3091)) |
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

Needs [Odin](https://odin-lang.org) (tested with `dev-2026-10`; `olt --version` prints the Odin and grammar versions a build was
verified with), `git`, `make` and a C compiler.

```bash
git clone --recurse-submodules https://github.com/RainerXE/odintooling
cd odintooling
(cd ffi/tree_sitter/tree-sitter-lib  && make)    # the tree-sitter libraries are build artefacts, not committed
(cd ffi/tree_sitter/tree-sitter-odin && make)
./scripts/build.sh        # → artifacts/<platform>/olt   (builds libsqlite3.a on first use)
```

To build and run every test suite in one go, use `./scripts/forgejo-ci.sh`. The tree-sitter grammar is pinned to
`tree-sitter-odin` v1.3.0; a library built from another version links silently and parses a different grammar, so the script
rebuilds both libraries from clean.

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
olt src/ --no-gitignore       # also scan files .gitignore excludes (default: skip them)
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
| C001 | Heap allocation (`make`/`new`) that nothing releases, returns, stores or hands on — judged by the [ownership analysis](#memory-ownership), not just a `defer` in the same block |
| C002 | Double-free or use-after-free |
| C009 | Import of `core:os/old`, which no longer exists in current Odin — use `core:os` |
| C010 | `Small_Array` can be replaced by the built-in `[dynamic; N]T` |
| C011 | FFI C resource (`ts_*_new`) without matching `defer ts_*_delete` |
| C101 | `context.allocator` reassigned without defer restore |
| C201 | Error return value discarded (unchecked result) |
| C202 | Switch on enum not exhaustive (requires `--export-symbols`) |
| C203 | `defer` in inner block fires before outer scope uses the handle |
| C031 | `panic()` on expected runtime failure — consider an error return (INFO) |

### Style

| Rule | What it catches |
|------|----------------|
| C003 | Procedure names must be `snake_case` |
| C007 | Type/struct/enum names must be `PascalCase` |
| C016 | Local variable names must be `snake_case` (default on) |
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

## Memory ownership

Odin has no garbage collector, so the question that matters is who frees what. olt answers it from the code, for every
allocation inside a procedure (`make`, `new`, `new_clone`, and the allocating calls in `mem`, `strings`, `fmt`, `os` and `slice`):

- **Which allocator** it comes from. `default` is `context.allocator`, so the caller owes a free. `param` is an `allocator`
  parameter, so the caller of *this* procedure owns the result. `temp` (`context.temp_allocator`) and `custom` (an arena, or a
  reassigned `context.allocator`) are released wholesale and owe nothing.
- **What became of it.** `freed_deferred`, `freed`, `returned`, `stored` (a field, a global, a map key, `append(&list, x)`),
  `passed` (given to another procedure) or `unfreed`.

Most Odin code allocates from the temp allocator or an arena on purpose, so "never freed" only means something for the default and
parameter allocators. Those, and only those, are flagged `leak_candidate`. A procedure that allocates and returns or stores the
memory gets the memory role `allocator`, one that allocates and frees it `borrower`, one that only frees `deallocator`.

Ask for it with `get_dna_context` (one procedure, with its callers and callees) or `get_ownership` (any allocation, filtered by
procedure, disposition or allocator). For a procedure that calls a factory and never releases the result:

```json
"ownership": {
  "factory": false, "frees_params": [], "keeps_params": [], "reads_params": [],
  "free_calls": 0, "leak_candidates": 1,
  "sites": [
    { "line": 13, "api": "slab_new()", "type": "pool.Slab", "allocator": "default",
      "var": "s", "disposition": "unfreed", "leak_candidate": true }
  ]
}
```

The same facts are in the graph database: `instantiates` edges (procedure → the type it allocates, with the ownership as JSON
`metadata`) and the `odin_alloc_site` table, so any query over the edges can ask which procedures create a `Thing`, and under which
ownership.

### Across procedures

- **Factories.** A procedure that returns memory it allocated from the default or a parameter allocator is a factory, and so is a
  wrapper that returns a factory's result, or a procedure group whose every member is one. A call to one is an allocation site of its
  caller (`api` is `name()`), owned through the allocator the caller passed, or the factory's own default when it passed none:
  `read_slice(f, n)` with `allocator := context.temp_allocator` owes nothing.
- **Parameters.** What a procedure does with a parameter decides what passing it there means. If it frees it, the caller's allocation
  is freed. If it stores or returns it, the caller no longer owns it. If it only reads it, the caller still does, so an allocation
  passed there and never freed is a leak. A parameter handed on to something the graph cannot see into (another package, a closure,
  an FFI call) is left as `passed`, and nothing is claimed.
- **Evidence from peers.** A caller that does not free a factory's result is only a `leak_candidate` when other callers of *that
  procedure* do. If nobody ever frees what `label_init` returns, the project's convention is not to (an arena, a parent that owns
  its children), and flagging every caller would be noise. On `todool` that withholds 115 sites, on `ols` 195.

### What it cannot see

`leak_candidate` is a pointer to read, not a verdict. On `ols` it flags 5 of 2,215 allocation sites, and a person has to look at
each. The analysis follows the *name* an allocation is bound to through the procedure, including local copies (`q := p`), composite
literals that carry it (`Registry{cache = buf}`) and pointers into it (`&xs[0]`). It does not know:

- **An arena installed by a caller.** If a caller sets `context.allocator` or hands in an arena, the callee's `make` looks like a leak
  and nothing in the callee says otherwise. olt's own MCP handlers are an example: the server passes each one its per-request temp
  allocator, so a handler's `make(..., allocator)` is released after the call. Silence a line like that with a reason:
  `// olt:ignore C001 request arena`.
- **What code outside the project does with a value**: other packages, closures held in variables, FFI. Those calls stay `passed`.
  On 18 public Odin repositories C001 reports 38 allocations the analysis does not call leaks: for 34 the value goes to code the graph
  cannot see into, for the other 4 the callee keeps it. C001 itself only uses what it can see in the file.
- **Which path runs.** Everything is syntactic. A free on any path counts as freed for the whole procedure, so an allocation freed
  on the happy path and leaked on an error path is not flagged. Making that precise needs path analysis; it is not done.

### Checking it on your project

The C001 lint rule asks this same analysis before it reports, so the two agree where they overlap. `scripts/crosscheck_c001.py
<project dir>…` compares them on a real project: where C001 flags an allocation the analysis sees handed on, or the analysis sees an
unreleased one C001 is silent about, one of the two is wrong. It found five bugs in olt while this was being built (one in C001, four in the analysis).

The graph is incremental, keyed on file content. When an olt release changes the analysis, a graph written by an older olt is
re-indexed in full on the next export (the graph records `olt_analysis_version`), because otherwise unchanged files would keep the
old answers. A graph olt never wrote to, such as one CodeGraph wrote, is left alone.

---

## Configuration — olt.toml

Run `olt init` in your project directory to generate one, or create it manually. Every section and key below is optional; an
unknown section or key is reported and ignored (it catches typos).

```toml
[domains]                 # opt-in rule groups (see Rules)
ffi             = true    # C011: FFI resource safety
odin_2026       = true    # C009/C010: APIs that changed in current Odin
stdlib_safety   = true    # C029/C033: stdlib allocation safety
semantic_naming = false   # C012: ownership naming hints
dead_code       = false   # C014/C015: unused procedures and constants
go_migration    = false   # C021-C023, C025: Go idioms

[naming]
c016 = true               # local variables must be snake_case
c019 = false              # type marker suffixes (opt-in)
c020 = false              # minimum name length (opt-in)
c020_min_length = 3
c020_allowed    = "i,j,k,x,y,z,n,ok,err,db,id"

[correctness]
c001_ownership_hints = true   # C001: INFO when an allocation is passed to another procedure (false silences it)

[tools]
ols_path = "/usr/local/bin/ols_lsp"   # OLS, if it is not in PATH

[ignore]
paths = "tests/,generated/"   # comma-separated path fragments to skip
```

Directory scans also skip whatever `.gitignore` excludes (`--no-gitignore` turns that off).

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
| `get_dna_context` | Callers, callees, memory role for a proc, and its ownership: allocations, factory or sink, leak candidates |
| `get_impact_radius` | Transitive impact of changing a symbol |
| `get_callers` / `get_callees` | Direct call graph neighbours |
| `search_symbols` | Full-text symbol search |
| `get_ownership` | Allocation sites: which allocator, and whether the memory is freed, returned, stored, passed on or leaked |
| `find_all_references` | Every location that references (calls) a symbol |
| `find_allocators` | Every procedure the graph tags as an allocator |
| `rename_symbol` | Generate rename patches across the project |
| `run_lint_denoise` | Lint an in-memory snippet and return structured fixes, for a fix-and-verify loop |

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
- **edges** — `contains` (file → declaration, enum → member), `calls`, `references` (procedure group → member) and `instantiates` (procedure → the type it allocates, with the ownership facts as JSON `metadata`)
- **unresolved_refs** — calls whose target is outside the project (`fmt::println`) or is a value (`a.b.f`)
- **files**, **nodes_fts** (full-text search), **project_metadata**, **schema_versions**

olt's own data lives beside them in `odin_*` tables, which CodeGraph never touches: `odin_node_info` (memory role and lint
findings per node), `odin_package` (the package each file declares), `odin_import` (what each file's qualifiers refer to),
and the ownership tables (`odin_alloc_site`, `odin_proc_ownership`, `odin_param_sink`, `odin_param_effect`, `odin_alloc_param`, `odin_site_via`; see [Memory ownership](#memory-ownership)).

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
                  C001–C203 rules ──── ownership analysis ──▶ .codegraph/olt.db
                                       (also feeds the MCP graph tools)
```

Symlinks created by `olt setup`:
- `ols → olt` — IDE OLS integration (argv[0] dispatch → LSP mode)
- `olt-lsp → olt` — backward compat
- `olt-mcp → olt` — backward compat

---

## Project layout

```
src/main.odin        Unified entry point (argv[0] + subcommand dispatch)
src/core/            Rule engine, CLI, config parsing, graph database, ownership analysis (ownership.odin)
src/mcp/             MCP server tools
src/lsp/             LSP proxy
ffi/tree_sitter/     Tree-sitter grammar + static libraries
ffi/codegraph/       CodeGraph's schema, vendored unmodified
vendor/odin-mcp      MCP protocol library (https://github.com/RainerXE/odin-mcp)
vendor/odin-sqlite3  SQLite bindings (https://github.com/RainerXE/odin-sqlite)
tests/               Rule test fixtures (tests/OWNERSHIP is the ownership fixture)
scripts/             Build and test scripts
ARCHITECTURE.md      Generated architecture map (arch/architecture.json is its declared model)
```

---

## Contributing

Build as described under [Build from source](#build-from-source), then run everything the project runs:

```bash
./scripts/forgejo-ci.sh      # builds the libraries and olt, runs every suite and the CodeGraph contract test
```

Individual suites are `scripts/run_*.sh` (one per rule, plus `run_ownership_tests.sh` and `run_gitignore_tests.sh`),
`scripts/test_m8_mcp.py` for the MCP tools (it needs `odin` on `PATH` for `run_odin_check`) and
`scripts/test_codegraph_contract.sh` for the CodeGraph compatibility (set `CODEGRAPH_BIN` to the CodeGraph to test against).

Before submitting:

- `olt src/` must report no violations. It lints its own source with the same rules.
- If you change what the ownership analysis records, regenerate `tests/OWNERSHIP/expected/` (the tests compare it exactly, so read
  the diff) and raise `ODIN_ANALYSIS_VERSION` in `src/core/graph_schema.odin`, so existing graphs are rebuilt.
- Add a fixture for the behaviour you changed: a case that failed before and passes now.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md). The release notes for the next version are in [docs/release-notes-0.98.0.md](docs/release-notes-0.98.0.md).

## License

olt is released under the zlib-style licence in [`LICENSE`](LICENSE). Third-party components keep their own
(permissive) licences; see [`NOTICE.md`](NOTICE.md).

> "The miracle is this: The more we share the more we have." — Leonard Nimoy
