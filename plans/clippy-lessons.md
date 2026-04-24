# Linting Landscape Survey — April 2026
*Research for odin-lint: what the best linters in other ecosystems are doing,
and what we can learn or adopt.*

---

## Executive Summary

The April 2026 linting landscape is defined by two macro-trends:

1. **The Rust-speed revolution** — Rust-written linters (Ruff, Biome, Oxlint) are
   10–1000× faster than their predecessors. This is not a marginal improvement; it
   changes what is feasible (sub-second feedback on million-line codebases, lint
   running on every keystroke not just on save). odin-lint already shares this
   advantage — Odin compiles to native, tree-sitter runs in C, and the binary has
   no runtime overhead.

2. **The type-awareness gap is closing** — The key unsolved problem for fast linters
   has always been: syntactic analysis is cheap, but catching real bugs requires type
   information. Biome v2 (June 2025) shipped its own type inference engine to avoid
   the TypeScript compiler cost. Oxlint is integrating `typescript-go` (the Go port
   of the TS compiler, 10× faster than tsc). This is the defining technical
   challenge of the era and directly maps to our M6 work.

---

## Rust / Clippy

**Status:** 800+ lints, feature freeze June–September 2025 (deliberately — focus on
quality over quantity). Resumed post-freeze.

**Key advances relevant to odin-lint:**

### Lint categories with configurable severity
Clippy's nine-tier system (correctness, suspicious, style, complexity, perf,
pedantic, restriction, nursery, cargo) is the industry standard reference for
rule organisation. Our two-tier (correctness, style) is simpler and fine for now,
but the `pedantic` and `restriction` concepts map directly to our opt-in C012.

### `clippy.toml` per-rule configuration
Clippy allows per-lint configuration: minimum complexity thresholds, allowed
method lists, disallowed patterns. This is the model for our planned `odin-lint.toml`.
Concrete lesson: **configuration keys should be scoped to the rule ID**, not global.

### MSRV (Minimum Supported Rust Version) awareness
Clippy won't suggest features newer than the project's configured MSRV. Our
equivalent: odin-lint should not fire C009/C010 (os2 migration, Small_Array) if the
project's `odin-lint.toml` declares a target Odin version older than dev-2026-04.
Add `target_odin_version` to the toml schema.

### The feature freeze lesson
Clippy entered a 12-week feature freeze in June 2025 due to lack of capacity
to maintain 750+ lints while adding new ones. The lesson is stark: **more rules
is not always better**. Each rule needs indefinite maintenance. Our approach of
~12 high-quality rules is healthier than racing toward a large count.

---

## Python / Ruff

**Status:** 10–100× faster than existing tools, over 500 rules, drop-in
replacement for Flake8, isort, Black, and more. Acquired by OpenAI (Codex team)
in March 2026.

**Key advances relevant to odin-lint:**

### Single binary, unified interface
Ruff replaced 10+ separate Python tools (Flake8, isort, Black, pyupgrade, etc.)
with one binary and one config file. This is exactly the odin-lint vision — a single
tool that does linting, formatting hints, and migration rules (C009/C010).

### `--fix` and `--unsafe-fix` distinction
Ruff distinguishes between safe automatic fixes (pure mechanical transformations with
no semantic change) and unsafe fixes (transforms that could change behaviour in edge
cases). Our M4.5 `--fix` / `--propose` split is the right equivalent. Consider
adding a `--unsafe-fix` tier for transforms like the C009 `core:os/old` → `core:os`
migration where the API surface changed.

### Rule codes with origin prefixes
Ruff prefixes rule codes with their origin: `E` (pycodestyle), `F` (Pyflakes),
`UP` (pyupgrade), `B` (flake8-bugbear), `RUF` (Ruff-native). This makes it
immediately clear where a rule comes from and why it exists. Our `C0XX`
(correctness), `S0XX` (style), naming is already good, but consider whether
`M009`/`M010` for migration rules would be clearer than reusing the `C` prefix.

### `ty` — the type checker as a separate tool
Astral also shipped `ty` in December 2025: an extremely fast Python type checker
and language server, written in Rust, designed as an alternative to mypy and
Pyright. The pattern — linter separate from type checker, both available
in the same toolchain — is exactly our CLI + OLS architecture.

---

## JavaScript/TypeScript / ESLint, Biome, Oxlint

This ecosystem is the most turbulent and has the most directly applicable lessons.

### The big three in April 2026

ESLint ended 2025 with 70.7M weekly npm downloads (65% growth), and v10.0.0
is in progress with a language-agnostic core architecture. It now officially
supports CSS and HTML linting alongside JS.

Biome v2 (June 2025) introduced type-aware linting that doesn't rely on the
TypeScript compiler. This is the most architecturally significant advance in
linting in years — a type inference engine written from scratch, avoiding the
compiler dependency entirely.

Oxlint is previewing type-aware linting via integration with typescript-go —
the Go port of the TypeScript compiler, which is 10× faster than tsc.

**Key lesson for odin-lint:** The type-awareness problem in JS/TS is structurally
identical to ours. Their solution — either build your own type inference or integrate
the language's compiler — is the same choice we face for M6. OLS is our "compiler
integration" path; it already has the full type-resolved AST. We should use it rather
than building type inference from scratch.

### GritQL — a pattern language for custom lint rules

Biome v2 shipped GritQL linter plugins. GritQL is now under the Biome
organisation. GritQL is a structural search and transform language — similar
to SCM queries but with a more developer-friendly syntax, using code snippets
rather than S-expressions.

```gritql
// GritQL example — matches and flags Object.assign() usage
`Object.assign($target, $source)` where {
  register_diagnostic(span = $target, message = "Prefer spread syntax")
}
```

Compare to our SCM equivalent:
```scheme
(call_expression
  function: (selector_expression
    field: (field_identifier) @fn (#eq? @fn "assign"))
  arguments: (argument_list) @args) @call
```

GritQL is more readable. SCM is more precise and already integrated.
**Recommendation:** Monitor GritQL's progress. If it adds Odin grammar support
(it uses tree-sitter under the hood), it could replace our SCM files with
something more accessible to rule contributors.

### Linter domains (Biome's killer feature for 2025)

Biome shipped "linter domains" — a way to group rules under umbrellas
and turn them on automatically based on your project's dependencies.

Example: if `biome.json` detects React as a dependency, the React rule domain
activates automatically. No manual configuration.

**Direct application to odin-lint:** The equivalent would be: if `odin-lint.toml`
declares `uses_ffi = true`, the C011 FFI Safety rules activate automatically.
If `odin_version = "dev-2026-04"`, the C009/C010 migration rules activate. This is
smarter than always-on rules and would dramatically reduce false positive noise.

Add `[domains]` to the `odin-lint.toml` schema:

```toml
[domains]
ffi = true        # enables C011 FFI safety rules
odin_2026 = true  # enables C009, C010 migration rules
semantic_naming = true  # enables C012
```

---

## Go / golangci-lint + staticcheck

**Status:** golangci-lint 2026.2.17 (released Feb 2026) includes staticcheck 0.7.0,
new gosec security rules (G117, G602, G701+), and `modernize` linter improvements.
go1.26 support landed in Feb 2026.

**Key advances relevant to odin-lint:**

### The meta-linter pattern
golangci-lint is not a linter — it is a **runner that executes 50+ linters in
parallel** and merges their output. Each linter is a specialist. The odin-lint
equivalent would be: after M6, expose a plugin API where external teams can write
odin-lint rules as separate binaries/packages that the runner discovers and executes.

### `errcheck` and `ineffassign` as separate focused tools
The Go ecosystem favours small, focused linters over monolithic ones. `errcheck`
does one thing: flags unchecked error returns. `ineffassign` does one thing: flags
assignments whose result is never used. Both are <10 lines of core logic. This
validates our approach of separate rules (C001, C002, C012) rather than one
"memory safety" mega-rule.

### The `modernize` linter — migration as a first-class concern
golangci-lint has a `modernize` linter that flags old Go patterns and suggests
modern equivalents — the exact concept behind our C009/C010 rules. It's treated
as a normal linter category, not special-cased. Lesson: **migration rules are
mainstream in mature lint ecosystems**, not exotic. We're on the right track.

---

## Java / Error Prone + NullAway + JSpecify

**Status:** Spring Framework 7 (Spring Boot 4) has migrated its entire
codebase to JSpecify annotations. JSpecify + NullAway is now the practical
standard for null safety in Java.

**Key advance relevant to odin-lint:**

### Annotation-driven ownership semantics
NullAway makes `@Nullable` the opt-in annotation — everything is assumed non-null
unless marked otherwise. JSpecify adds `@NullMarked` at the package level to opt
entire packages into null-safe analysis.

This is structurally identical to our C012 `_owned` / `_borrowed` naming convention.
The Java ecosystem solved the ownership annotation problem with source-level
annotations; we're solving it with naming conventions. Both approaches encode
semantics that the type system doesn't express. The lesson: **an opt-in mechanism
that signals ownership is valuable enough that both Java (billion-line codebases)
and Odin (system programming) need it**. C012 is not a fringe idea.

The difference is that JSpecify annotations are machine-verifiable at compile time.
Our naming conventions are only machine-verifiable by the linter. This reinforces
why C012 needs to be a lint rule, not just a style guide.

---

## Cross-Ecosystem Patterns — What to Adopt

Based on all of the above, here are concrete actionable items for odin-lint, ordered
by priority:

| # | Pattern | Source | odin-lint action | Milestone |
|---|---------|--------|-----------------|-----------|
| 1 | **Linter domains** — auto-enable rules based on project config | Biome | Add `[domains]` to `odin-lint.toml`; auto-enable C011 when `ffi=true`, C009/C010 when `odin_2026=true` | M4 (config) |
| 2 | **`--unsafe-fix` tier** — fixes that change API surface | Ruff | Add `--unsafe-fix` flag for C009 migration (os2 API is different, not identical) | M4.5 |
| 3 | **MSRV / target version awareness** | Clippy | `target_odin_version` in `odin-lint.toml`; suppress migration rules for older targets | M4 (config) |
| 4 | **Rule origin prefix** — migration rules vs correctness | Ruff | Consider `M009`/`M010` instead of `C009`/`C010` for migration rules | M4 (--list-rules) |
| 5 | **Plugin/domain API** — external rule packages | golangci-lint | Post-M6; define stable rule API for external contributors | Post-M6 |
| 6 | **GritQL** — more readable pattern language | Biome | Monitor; evaluate if Odin grammar support is added | Post-M6 |
| 7 | **Quality over quantity** — feature freeze model | Clippy | Enforce: never add a rule without a full fixture + false-positive analysis | All milestones |

---

## The Biggest Insight: Type-Aware Linting Is the Frontier

Every ecosystem is wrestling with the same problem: **syntactic linting is fast
and catches style issues; type-aware linting catches real bugs but is slow.** The
solutions being explored:

- **Build your own type inference** (Biome) — 6+ person-years of work, 85%
  coverage vs full compiler
- **Integrate the compiler, make it faster** (Oxlint + typescript-go) — depends
  on external team's progress
- **Use the language server** (our M6 plan with OLS) — OLS already has the full
  type-resolved AST; we just need to consume it

**Our approach (M6 via OLS) is the right one.** We don't build type inference
ourselves, and we don't wait for the compiler to get faster. OLS is already fast
and already has the information. The C012-T rules and C101/C201/C202 all use this
path.

---

*Research date: April 2026*
*Next review: When ESLint v10.0 goes stable (est. Q2 2026) and Oxlint typed rules
ship (est. Q3 2026)*
