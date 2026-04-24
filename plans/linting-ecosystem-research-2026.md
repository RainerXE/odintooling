# Linting Ecosystem Research — April 2026
*State of the art across Rust, Python, JS/TS, Go, and Java*
*Written for odin-lint — "best of breed" reference document*

---

## Why This Matters

odin-lint is a linter for a niche language at a pivotal moment: the entire
linting ecosystem is undergoing a major architectural shift in 2025-2026.
Understanding *why* the best tools are winning — not just *what* they do —
is what lets us make the right decisions for odin-lint's remaining milestones.

The headline finding: **the three winning tools across all ecosystems share
exactly one architectural property — they do semantic analysis in the same
pass as parsing, rather than treating linting as a post-processing step on
already-parsed ASTs.**

---

## Rust: Clippy

**Status:** 800+ lints, the gold standard for opinionated correctness linting.
In June 2025, Clippy entered a 12-week feature freeze — not because it's done,
but because *750+ lints is hard to maintain*. The team explicitly paused new
features to reduce false positives and improve edge-case coverage on existing
rules.

**What odin-lint should learn:**

1. **The feature freeze lesson is real.** Clippy froze at 750 lints because
   maintaining breadth degrades quality. odin-lint's plan — correctness rules
   first, style rules as opt-in, type-gated rules deferred to M6 — is the right
   discipline. Rule quality over rule count.

2. **EarlyLintPass vs LateLintPass is the exact same split as our tree-sitter
   vs OLS distinction.** Clippy runs two pass types: EarlyLintPass (AST only,
   before type checking — fast, less precise) and LateLintPass (after type
   resolution — slower, catches semantic bugs). Our M3/M4 rules = EarlyLintPass.
   Our M6 rules (C101, C201, C202, C012-T) = LateLintPass. This is not
   coincidence — it's the universal architecture for linters that care about
   correctness.

3. **MSRV (Minimum Supported Version) awareness.** Clippy lets users set a
   minimum compiler version so lints don't suggest syntax the project's toolchain
   can't compile. odin-lint should do the same for Odin: C009/C010 migration
   rules should be suppressible if the project targets a pre-2026 Odin version.

---

## Python: Ruff (Astral)

**Status:** 800+ rules, 10-100x faster than Flake8/Pylint. Replaces Flake8,
isort, pyupgrade, autoflake, and more in a single binary. v0.15 (Feb 2026)
adopted the 2026 Python style guide. Astral (Ruff's creator) was acquired by
OpenAI's Codex team in March 2026 — significant for the AI tooling angle.

**What odin-lint should learn:**

1. **One binary, one config, multiple tool categories.** Ruff doesn't just lint
   — it formats, sorts imports, upgrades syntax, and removes dead code. The
   "single tool" story massively reduces adoption friction. odin-lint's roadmap
   already follows this: CLI → autofix (M4.5) → OLS integration (M5) → MCP (M5.5).
   Do not let these ship as separate binaries.

2. **The "upgrade" rule category is high-value.** Ruff's `pyupgrade` rules
   flag old Python syntax and auto-fix it to modern equivalents. odin-lint's
   C009/C010 are exactly this — "migrate from legacy pattern to modern idiom."
   This is not a niche use case. It's one of the highest-value rule categories
   in every ecosystem. Consider making a formal `migration` tier alongside
   `correctness` and `style`.

3. **Sub-second feedback loops are a UX requirement, not a nice-to-have.**
   Ruff's value proposition is speed — it lints the entire CPython codebase in
   under 1 second. On a 1000-file Odin project, odin-lint must return in < 2
   seconds or developers turn it off. The SCM query migration (M3.1) and
   file-once-read pattern (C001/C002) are the right moves; track performance
   benchmarks from M4 onward.

4. **Astral acquired by OpenAI Codex team (March 2026).** The trajectory is
   clear: fast local linting + AI code generation are converging. Ruff's
   `--format json` output feeds AI tools directly. odin-lint's `--format json`
   (M4.1) and MCP gateway (M5.5) are on the right side of this convergence.

---

## JavaScript/TypeScript: Oxlint + Biome v2

This ecosystem had the most dramatic architectural developments in the last 12 months.

### Oxlint (VoidZero / Evan You)

**Status:** v1.0 stable (June 2025), 715+ rules, 50-100x faster than ESLint.
Built on the Oxc compiler stack — same AST used for bundling, transformation, and linting.

**Key architectural innovation:** Oxlint's `LintContext` uses `Deref` to expose
the *Semantic* struct directly to every rule. Rules don't re-walk the AST — they
query the already-computed symbol table. A rule like `no-unused-vars` calls
`ctx.scoping().symbol_flags(symbol_id)` rather than traversing children manually.

**What odin-lint should learn:**

1. **Pre-computed semantic data passed to rules as context.** When OLS provides
   the `^ast.File` in M5, the rules shouldn't re-walk it — they should receive
   a pre-computed `SemanticContext` struct that already has scope information,
   symbol resolution, and type data. Building this context once per file and
   sharing it across all rules is the Oxlint architecture. Design the M5 rule
   interface around this pattern.

2. **Allocator pool per worker thread.** Oxlint maintains a pool of allocators
   — one per thread — resetting between files rather than allocating fresh.
   This keeps memory warm in CPU cache. For odin-lint's parallel file processing
   (post-M4), consider the same pattern.

3. **"Linter domains"** — Biome v2's concept of grouping rules by framework
   dependency (React rules only enable if React is detected as a dependency).
   odin-lint equivalent: C009/C010 migration rules auto-disable if the project
   is already on the correct API (detected by absence of `core:os/old` imports).

### Biome v2 (June 2025, codename "Biotype")

**Status:** The first type-aware linter to NOT require the TypeScript compiler.
Built its own type inference engine. Detects ~75-85% of cases that full tsc
would catch. Sponsored by Vercel. Also introduced GritQL plugins, linter domains,
and a "Scanner" for cross-file module graph analysis.

**Key architectural innovation:** Biome's Scanner is opt-in — it only activates
when a "project domain" rule (like `noImportCycle`) is enabled. When inactive,
linting is instant. When active, it builds a module graph once and shares it
across all rules. This is the correct design for expensive analysis.

**What odin-lint should learn:**

1. **Build a type inference engine rather than waiting for the full compiler.**
   Biome proved you don't need to invoke `tsc` to get useful type-aware rules.
   For odin-lint M6, OLS is the type oracle (no need to build our own inference).
   But the *design pattern* — call the type oracle once per file, cache results,
   share with all rules — is directly applicable.

2. **The Scanner / opt-in project analysis is the exact design for M5.6.**
   Biome's Scanner builds a cross-file module graph only when needed. odin-lint's
   DNA exporter + call graph (M5.6) should follow the same opt-in pattern:
   `--export-symbols` triggers it; normal `odin-lint ./src` does not.

3. **GritQL for plugins** — Biome uses GritQL (a graph query language for code)
   for plugin patterns. This is more powerful than plain SCM queries because it
   can express cross-node relationships. Worth watching for post-M6 odin-lint
   plugin system design.

---

## Go: golangci-lint v2 + staticcheck 0.7

**Status:** golangci-lint v2 (March 2025) merged staticcheck, stylecheck, and
gosimple into one unified `staticcheck` linter. v2.2.17 (Feb 2026) updated
gosec with new security rules (G117, G602, G701). godoc-lint integrated in
golangci-lint v2.5+ (2026).

**What odin-lint should learn:**

1. **The meta-linter pattern wins.** golangci-lint doesn't write rules — it
   aggregates other linters and runs them in parallel with unified output.
   odin-lint's Rule struct + runner is this pattern applied to a single language.
   The key insight: *unified output format is more valuable than unified
   implementation*. SARIF output (M4.1) is the industry-standard format for this.

2. **golangci-lint v2's `migrate` command** generates a new config from an old
   one during major version upgrades. When odin-lint rules change significantly
   (e.g. when migration rules C009/C010 are added), a `odin-lint migrate` command
   that updates `odin-lint.toml` is worth adding to M4.

3. **`godoc-lint` integration** (2026) — Go is now linting documentation
   consistency at the toolchain level. odin-lint C006 (public API procs must have
   doc comments) is this same idea. Worth making C006 one of the first non-stub
   rules after M3.3.

---

## Java: Error Prone + SpotBugs

**Status:** SpotBugs 4.9.8 (Oct 2025), JDK 21 support. Error Prone still the
gold standard for compile-time Java analysis (integrated into the compiler
itself). NullAway (companion to Error Prone) is the best null-safety checker.

**What odin-lint should learn:**

1. **Bytecode analysis catches what source analysis misses.** SpotBugs works on
   compiled `.class` files, not source — this means it catches issues related to
   type erasure and compiler optimisations. For odin-lint, the analogous insight
   is: **OLS type resolution (M6) will catch things that tree-sitter SCM queries
   (M3) structurally cannot** — not because OLS is smarter, but because it has
   access to a richer representation. The M3/M6 split is architecturally sound.

2. **Error Prone as a compiler plugin, not a separate tool.** Error Prone runs
   inside `javac` — same pass, no extra invocation. The LSP call hierarchy idea
   (integrate with OLS rather than running separately) is the same instinct. The
   best linting is invisible infrastructure, not a separate tool you have to
   remember to run.

3. **SARIF as universal output.** SpotBugs, golangci-lint, ESLint, Ruff —
   all support SARIF output for GitHub Actions / VS Code integration. SARIF in
   M4.1 is not optional if odin-lint wants to be taken seriously in CI pipelines.

---

## The Five Universal Patterns (2025-2026)

Across all five ecosystems, the tools winning in 2026 share these five properties:

### 1. Rust-speed parsing as infrastructure

Ruff (Python), Oxlint/Biome (JS/TS), golangci-lint (Go via Go's native compiler
speed) — the winners are all compiled-language implementations of the parser.
odin-lint is already on this path: tree-sitter is written in C, and Odin compiles
to native code. The SCM query engine (M3.1) further leverages tree-sitter's
compiled query execution.

### 2. Semantic context passed to rules, not re-computed per rule

The winning architecture: parse once → compute semantic data once → pass to all
rules. Oxlint's `LintContext → Semantic` deref, Biome's Scanner, Clippy's
`LateLintPass` with full type info. odin-lint M5 must design the OLS rule
interface around this pattern. The `C001ScopeContext` in the current implementation
is the right shape — extend it rather than redesign it.

### 3. Two-tier execution: fast pass + slow semantic pass

Every ecosystem has converged on two tiers:
- **Tier 1 (fast):** syntactic, no type info, sub-second — Clippy EarlyLintPass,
  Ruff rules, Oxlint non-type-aware rules
- **Tier 2 (slow, opt-in):** semantic, cross-file, type-aware — Clippy LateLintPass,
  Biome Scanner, typescript-eslint

odin-lint's tree-sitter CLI path = Tier 1. OLS plugin path = Tier 2.
This is correct. Don't blur the boundary.

### 4. Autofix as a first-class citizen

Every winning tool ships `--fix` alongside lint rules. Ruff, Clippy, Oxlint,
golangci-lint all have it. Autofix is not an afterthought — it's what makes
linting tolerable on a legacy codebase. odin-lint M4.5 (autofix layer) is on
the right schedule: rules must be stable first, then fixes follow.

### 5. SARIF output for CI/editor integration

SpotBugs, golangci-lint, Ruff, ESLint — all support SARIF 2.1.0. GitHub Actions,
VS Code Problems panel, and GitLab SAST all consume SARIF. This is now a
hard requirement for any linter that wants to be used in professional CI pipelines.
odin-lint M4.1 must include SARIF.

---

## What odin-lint Does That Nobody Else Does

Reading the ecosystem makes one thing clear: **no existing linter has a semantic
export layer feeding an AI model.** The DNA exporter (M5+) is genuinely novel:

- Ruff can tell you what's wrong. It cannot tell an AI *why* a procedure is an
  allocator or what its ownership semantics are.
- Clippy has 800 rules. None of them produce a call graph consumable by a RAG
  pipeline.
- Biome has type inference. It has no `symbols.json` that a fine-tuned model
  can use as system context.

The hybrid graph-RAG architecture (M5.6) — AST structural graph + vector
embeddings + lint violation quality signal — is the odin-lint differentiator.
Every other linter stops at "here is the diagnostic." odin-lint adds "here is
the semantic context for an AI to reason about your entire codebase."

---

## Recommended Plan Updates

Based on this research, three concrete additions to the V7 plan:

**1. Add `migration` as a formal rule tier** (update Section 9)
Rules C009 and C010 are not style rules and not correctness violations —
they're deprecation migrations. A `migration` tier (between `style` and
`correctness`) with its own emoji (🔄) and default-warn behaviour makes the
taxonomy cleaner and matches how Ruff categorises its `pyupgrade`-equivalent
rules.

**2. Add SARIF to M4.1 gate criteria** (already planned, make it explicit)
SARIF 2.1.0 is now a hard requirement for professional CI use. The M4.1 gate
should say: "SARIF output accepted by GitHub Actions problem matcher" — not just
"SARIF supported."

**3. Add `SemanticContext` design to M5 task list** (new task)
Before implementing M5 OLS plugin rules, design a `SemanticContext` struct that
is built once per file from `^ast.File` and passed to all rules — mirroring
Oxlint's `LintContext → Semantic` pattern. Rules should query the context, not
re-walk the AST. This is a design task, not a coding task, and should happen
before any M5 rule code is written.

---

## Sources

- Clippy feature freeze announcement: blog.rust-lang.org (June 2025)
- Ruff v0.15 release notes: astral.sh/blog (Feb 2026)
- Astral/OpenAI Codex acquisition: astral.sh (March 2026)
- Oxlint v1.0 stable: infoq.com (Aug 2025); oxc.rs (2026)
- Oxlint architecture: readoss.com (April 2026)
- Biome v2 "Biotype" release: biomejs.dev (June 2025)
- Biome roadmap 2026: biomejs.dev
- golangci-lint v2 changelog: golangci-lint.run (March 2025)
- SpotBugs 4.9.8: spotbugs.github.io (Oct 2025)
- "If I Wrote a Linter": joshuakgoldberg.com (updated June 2025)

---

*Created: April 2026*
*For: odin-lint V7 planning — best-of-breed reference*
*Next review: when Biome v2.4+ ships HTML stable (Q2 2026)*
