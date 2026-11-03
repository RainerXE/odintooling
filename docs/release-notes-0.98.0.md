# olt 0.98.0 — release notes (draft)

> **Status: draft, not released.** The version in the source is still `0.97.3`. To release: raise `OLT_VERSION` in
> `src/core/cli.odin`, rename the `[Unreleased]` heading in `CHANGELOG.md` to `[0.98.0]` with the date, tag, and publish these notes.
> The version is a minor bump because an upgrade changes the graph database, the licence and some C001 output; see *Upgrading*.

## What this release is

olt is now an Odin-specific alternative to [CodeGraph](https://github.com/colbymchenry/codegraph) that can answer the question
Odin makes you ask: **who frees this?** Its code graph is a CodeGraph database, so CodeGraph's tools read it, and it records, for
every allocation, which allocator it came from and what became of the memory.

## Highlights

- **Memory ownership in the graph.** Every `make`, `new`, `new_clone` and allocating `mem`/`strings`/`fmt`/`os`/`slice` call is
  recorded with its allocator (`default`, `param`, `temp`, `custom`) and its fate (`freed_deferred`, `freed`, `returned`, `stored`,
  `passed`, `unfreed`). Ask for it with the new `get_ownership` tool, or per procedure through `get_dna_context`. Memory the default or a
  parameter allocator owns and nothing releases is flagged `leak_candidate`.
- **Followed across procedures.** Factories (procedures that return memory they allocated, and wrappers around them) and what a
  procedure does with each parameter (frees, keeps or only reads it) are tracked, so `t := make_thing()` and `consume(t)` mean what they
  say. A caller is only suspected where its peers free what the factory returns, which keeps arena- and parent-owned code quiet.
- **C001 is smarter.** It asks the same analysis before it reports. Allocations returned inside a tuple or as a slice, stored into a
  field or list, freed on another path or in a `defer { ... }` block, or drawn from an arena, no longer produce reports; allocations
  nothing touches are reported even where the old heuristics stayed quiet.
- **The graph is a CodeGraph database.** CodeGraph's schema (v16) vendored unmodified, tested against a real CodeGraph (open, query,
  sync). `olt --codegraph-init .` writes it where CodeGraph looks, for a CodeGraph that does not index Odin yet.
- **Better Odin resolution.** A bare call resolves only inside its package (a directory); `pkg.fn()` resolves through the file's imports;
  procedure groups are one node with `references` edges. Against CodeGraph's own Odin index, olt has 95% (odin-http) and 96% (ols) of
  its distinct call edges, up from 79% and 85%.
- **Directory scans honour `.gitignore`**, read by git itself.

## Upgrading from 0.97.3

| What changes | What you do |
|---|---|
| **Licence** is now zlib-style (was MIT). `NOTICE.md` lists third-party components. | Check it suits you. |
| **The graph database** is now a CodeGraph database, default `.codegraph/olt.db`. A database from an older olt is rebuilt automatically. | Nothing. The first export re-indexes the project once. |
| **Analysis changes** re-index a graph written by an older olt in full on the next export. | Nothing. It happens automatically, once per analysis change. |
| **`--codegraph-init` / `--codegraph-sync`** run the normal export into `.codegraph/codegraph.db` instead of converting a second database. | Update scripts that relied on the old two-database behaviour. |
| **Scans skip what `.gitignore` excludes** (including tracked files that match an ignore pattern). | `--no-gitignore` restores the old behaviour. |
| **C001 output changes.** Fewer false reports, and a few new ones for allocations nothing touches (including `return len(xs)` and a parameter allocator). | Expect a different list; `olt --explain C001` says exactly when it reports. |
| **A CodeGraph reindex drops olt's own tables** (ownership, roles). | Run `olt --export-symbols` again. |

## New and changed in detail

**MCP tools.** New: `get_ownership`. Changed: `get_dna_context` now includes ownership, `get_impact_radius` follows callers (it used to
return callees). `find_all_references`, `find_allocators` and `run_lint_denoise` are documented in the README.

**Rules.** C001 as above. C009 and C010 messages now say only what holds in Odin `dev-2026-10`. The built-in `--explain C001` text is
rewritten to match the rule.

**Tooling.** `scripts/crosscheck_c001.py` compares the lint rule with the graph on any project. `scripts/test_codegraph_contract.sh`
checks compatibility with a real CodeGraph. `scripts/forgejo-ci.sh` builds, runs every suite and the contract test.

**Fixed.** A real crash in the LSP proxy (a read past tree-sitter's capture-name buffer); CodeGraph failing to `sync` an olt-written
database (`duplicate column name`); calls after a nested procedure attributed to it; duplicated unresolved references on every
incremental export; phantom duplicate nodes for every member of a procedure group; and a CI job that called build scripts that do
not exist. The full list is in `CHANGELOG.md`.

## Known limits

- **`leak_candidate` is a pointer, not a verdict.** The analysis is syntactic and per procedure plus the project's own call graph.
  It cannot see an arena a caller installed, or what code outside the project does with a value (other packages, closures, FFI).
  On `ols` it flags 5 of 2,215 allocation sites.
- **C001 only uses what is in the file** it is linting. On 18 public Odin repositories it reports 38 allocations the graph does not call
  leaks: 34 go to code the graph cannot see into, in 4 the callee keeps the value.
- **A free on any path counts as freed for the whole procedure.** An allocation freed on the happy path and leaked on an error path is
  not flagged; that needs path analysis, which olt does not do.
- **Two `olt.toml` keys are accepted but not read**: `[target] odin_version` and `[tools] odin_path` (`run_odin_check` takes its
  compiler path as a tool argument).
- **Calls through values** (`obj->f()`, a procedure stored in a variable) are recorded as unresolved, not guessed.

## Verified with

- Odin `dev-2026-10`, tree-sitter-odin `v1.3.0`, CodeGraph `1.6.2` (schema v16).
- Linux and macOS: every rule suite, the MCP and config tests, the ownership and `.gitignore` suites, and the CodeGraph contract test.
- Measured on 18 public Odin repositories, including Odin's own `core`, `ols`, `odin-http`, `karl2d`, `todool` and `ravn`.
