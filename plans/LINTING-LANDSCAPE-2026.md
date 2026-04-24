# Linting Landscape 2025–2026: State of the Art
*Research document for odin-lint design reference*
*Compiled: April 2026*

---

## Why This Document Exists

odin-lint aims to be best-of-breed for Odin. To achieve that, it must know what
"best of breed" currently means across the broader linting ecosystem. This document
surveys the April 2026 state of linting in Rust, Python, JavaScript/TypeScript, Go,
and Java — identifying the techniques, architectures, and innovations that are worth
adopting or learning from.

---

## The Big Picture: What 2025–2026 Changed

Three shifts define the current era:

**1. Rust-native speed is now the baseline expectation.**
Ruff (Python), Biome and OXC (JS/TS), and golangci-lint are all either written in
Rust or rely on Rust-based parsers. The performance bar has moved: sub-second
feedback on 100k-line codebases is now expected, not impressive. Any new linter
that cannot meet this bar is dismissed regardless of rule quality.

**2. Type-aware linting without invoking the compiler is the frontier.**
The hardest problem in linting is getting type information cheaply. The traditional
approach (invoke the full compiler, parse its output) is too slow for interactive
feedback. The 2025-2026 frontier is linters that build their own lightweight type
models — Biome v2 (June 2025) achieved type-aware linting without invoking `tsc`.
This is architecturally significant: it means you can have type-aware rules at
tree-sitter speed.

**3. AI-powered autofix is crossing from research into production.**
ByteDance's BitsAI-Fix (Aug 2025, arXiv:2508.03487) deployed LLM-driven lint
autofix at enterprise scale: 85% repair accuracy, 12,000+ issues resolved
automatically. Semgrep's AI Assistant achieves 96% agreement with human triage
across 6 million security findings. AI is no longer "future work" in linting — it
is happening at scale.

---

## Rust: Clippy

**Status:** Gold standard for correctness linting. 750+ lints, 10 categories,
ships with the Rust toolchain. Every Odin developer who has used Rust has used
Clippy — it is the primary reference for odin-lint's design.

**2025–2026 developments:**
- **Feature freeze (June–Sept 2025):** The Clippy team announced a 12-week feature
  freeze at Rust 1.89 to address maintenance debt from 750+ lints. The lesson:
  rule volume has a maintenance cost. Every lint that ships needs to be maintained
  against all future compiler changes forever. Quality over quantity.
- **MSRV-aware linting:** Clippy can now be configured with a minimum supported
  Rust version (`clippy.toml` or inner attribute), and lints that suggest features
  not available in the MSRV are silenced. Directly applicable to odin-lint:
  a `[rules]` section in `odin-lint.toml` could specify the target Odin version
  so migration rules (C009, C010) only fire for codebases targeting pre-2026 Odin.
- **`klint`:** A new complementary linter specifically for Rust-in-Linux-kernel
  work, focusing on lock correctness. Shows the pattern of domain-specific linters
  as companions to general-purpose ones.

**Key lessons for odin-lint:**
- The lint category taxonomy (correctness / suspicious / style / complexity / perf /
  pedantic / restriction) is the best-in-class model. odin-lint's current
  correctness/style split should eventually expand to include perf and complexity.
- Autofix (`cargo clippy --fix`) is deeply integrated, not bolted on. The FixEdit
  layer (M4.5) should be designed from day one as a first-class path.
- Machine-applicable vs. suggestion-only fixes are distinguished in Clippy. In
  `--format json` output, mark each diagnostic with `fixable: true/false`.

---

## Python: Ruff + `ty`

**Status:** Ruff has won. It replaced Flake8, isort, Black, pyupgrade, and more in
a single binary. 500+ rules, 10–100× faster than the tools it replaced, built in
Rust. It is the reference for "what does consolidation look like."

**2025–2026 developments:**
- **Ruff v0.15 (Feb 2026):** PEP 758 support (Python 3.14 unparenthesized except
  blocks), formatter alignment with Black, continued rule expansion.
- **`ty` (Dec 2025):** Astral released `ty`, a blazing-fast Python type checker and
  language server written in Rust, designed as an alternative to mypy/Pyright.
  Beta in early 2026. Key: a *separate* tool for type checking, not folded into
  Ruff. The linter and the type checker are distinct tools with a clean interface
  between them. This is relevant for odin-lint's M6 design: `odin-lint` lints,
  OLS type-checks. Keep them separate.
- **OpenAI acquisition (March 2026):** Astral (Ruff, uv, ty) entered agreement
  to join OpenAI's Codex team. Short-term: development continues. Long-term:
  trajectory uncertain. Lesson: do not build hard dependencies on commercial
  tooling whose ownership can change.

**Key lessons for odin-lint:**
- **Consolidation wins.** Ruff replaced 8+ tools. For Odin, odin-lint should aim
  to be the single tool for static analysis — not one of many. The DNA export,
  MCP gateway, and autofix layer all push in this direction.
- **Inline suppression syntax matters.** Ruff's `# noqa: E501` syntax is consistent,
  machine-parseable, and well-documented. odin-lint's `// odin-lint:ignore C001`
  is already well-designed on this axis.
- **Rule codes are searchable.** Ruff's `E`, `W`, `F`, `I` prefixes make rule
  categories scannable. odin-lint's `C0XX` / `C1XX` / `C2XX` structure is correct.

---

## JavaScript/TypeScript: Biome v2, OXC/Oxlint, ESLint v9

**Status:** Three-way competition in 2026. ESLint v9 (flat config, 50M+ weekly
downloads) remains the ecosystem default. Biome v2 is the fastest all-in-one
challenger. Oxlint (from the OXC project) is 50–100× faster than ESLint but
rule coverage is still catching up.

**2025–2026 developments:**

**Biome v2 (June 2025):**
- **Type-aware linting without `tsc`** — the most architecturally significant
  development in JS/TS linting in years. Biome built its own lightweight type
  model from the AST, enabling type-aware rules at linter speed rather than
  compiler speed. For odin-lint: the M6 type-gated rules (C012-T1, C012-T2,
  C101, C201) currently depend on OLS. Biome's approach shows it may be possible
  to build a lightweight Odin type model within odin-lint itself, avoiding the
  OLS dependency for some type checks.
- 340+ rules, formatter (97% Prettier-compatible), all in one binary.
- VCS integration for cache consistency — same git hook approach as CodeGraph.

**Oxlint v1.0 (June 2025):**
- 50–100× faster than ESLint. No Node.js required (Rust binary).
- The architecture: a shared parser (OXC) as the foundation, with linting, 
  formatting, and transformation as separate tools using the same parse tree.
  This is the correct architecture for a language tooling suite.
- `tsgolint` (TypeScript-Go-based linter): experimental in OXC, planned for
  Q3–Q4 2025, enabling type-aware rules with 10× faster type-checking than tsc.

**ESLint v9:**
- Flat config (`eslint.config.js`) is now the default. Legacy `.eslintrc` deprecated.
- 4000+ plugins in the ecosystem — this breadth is ESLint's moat.

**Key lessons for odin-lint:**
- **Shared parser as the foundation.** The OXC model — one parser, multiple tools
  — is the right long-term architecture for odintooling. Today odin-lint and OLS
  each parse Odin separately. Eventually a shared `odin-parser` library serving
  both would be the right move (though this is a large undertaking).
- **Type-aware linting without full compiler is achievable.** Biome proves this for
  TS. Worth investigating for Odin: a lightweight type resolver for the most common
  cases (is this a `mem.Allocator`? is this a `mem.Arena`?) could enable C012-T1
  and C012-T2 without waiting for M6 OLS integration.
- **Auto-fix coverage matters.** OXC is still catching up on autofix. Biome has
  extensive autofix. Users will prefer tools with autofix even if accuracy is
  slightly lower. Prioritise the FixEdit layer (M4.5).

---

## Go: golangci-lint + staticcheck

**Status:** golangci-lint is the de facto standard — an aggregator running 50+
linters in parallel. staticcheck is the gold-standard single-tool deep analyser
(150+ checks, maintained by Dominik Honnef, extremely low false positive rate).
Together they cover the Go ecosystem comprehensively.

**2025–2026 developments:**
- **golangci-lint go1.26 support (Feb 2026):** Tracks the Go release cadence closely.
- **New gosec rules (Feb 2026):** G117, G602, G701–G706 — injection and crypto
  vulnerability patterns. Reflects the growing emphasis on security linting.
- **`unqueryvet` new options:** `check-n1`, `check-sql-injection`, `check-tx-leaks`
  — SQL-aware linting is becoming standard. Shows that domain-specific rule sets
  within a general linter are viable.
- **`modernize` linter:** Flags outdated Go patterns for replacement with current
  idioms — the direct analogue of odin-lint's C009/C010 migration rules.
- **`revive` new rules (Feb 2026):** `epoch-naming`, `use-slices-sort` — naming
  and stdlib modernisation rules are actively added.

**Key lessons for odin-lint:**
- **The aggregator model.** golangci-lint does not write rules; it coordinates
  other tools. As odin-lint grows, consider whether rules should be pluggable
  (loaded from `.dylib`) rather than all compiled in. The plugin system in
  `plugin_main.odin` already points this direction.
- **`modernize` as a rule category.** A dedicated "modernise" or "migrate" tier
  in odin-lint (C009, C010 are already this) is a recognised pattern in Go.
  Consider making it a first-class tier in `odin-lint.toml`.
- **SARIF output is expected.** golangci-lint, staticcheck, Semgrep all output
  SARIF. odin-lint's M4.1 `--format sarif` is the right call.

---

## Java: SpotBugs + Error Prone + Semgrep

**Status:** Java's static analysis is the oldest and most mature. SpotBugs
(bytecode analysis), Error Prone (compile-time analysis), and Checkstyle/PMD
(style) form the traditional stack. Semgrep has entered Java's ecosystem with
cross-file dataflow analysis.

**2025–2026 developments:**
- **SpotBugs 4.9.8 (Oct 2025):** JDK 21 support, active maintenance. Bytecode
  analysis catches issues that source-level analysis misses (type erasure effects,
  compiler optimisations). For Odin: this is not directly applicable since Odin
  compiles to native binaries without an intermediate bytecode format.
- **Error Prone + Refaster:** Google's approach — compiler plugin + Refaster
  (structural code transformation templates) for automated migration. Refaster
  is essentially a type-safe autofix system. The M4.5 FixEdit layer is odin-lint's
  equivalent.
- **Semgrep cross-file dataflow (2025–2026):** Semgrep Pro Engine's cross-file
  taint tracking is now available for Java. 72–75% vulnerability detection vs
  44–48% for single-file analysis. The lesson: cross-file analysis dramatically
  improves correctness rule quality. The DNA export (M5.6) enables this for
  odin-lint by making the call graph queryable.
- **OpenGrep fork (Jan 2025):** Community fork of Semgrep that restores
  cross-function taint analysis moved behind Semgrep's commercial wall. Shows the
  risk of features being commercialised away from open source users.

**Key lessons for odin-lint:**
- **Bytecode vs source analysis is a false choice for Odin.** Odin's compiler
  produces native code with no bytecode layer. All Odin static analysis must be
  source-level. This is why the OLS type-resolution path (M6) is the right
  architecture rather than trying to analyse compiled output.
- **Cross-file analysis is where the real bugs are.** Semgrep's 50% improvement
  from single-file to cross-file analysis is striking. The DNA call graph (M5.6)
  is the foundation for odin-lint eventually supporting cross-file rules.
- **SARIF is universal.** SpotBugs, Semgrep, Ruff, golangci-lint — all output
  SARIF. GitHub Actions, VS Code, and every CI system reads it natively.

---

## AI-Powered Linting: The Emerging Frontier

**BitsAI-Fix (ByteDance, Aug 2025 — arXiv:2508.03487):**
The most important paper in this space. Deployed LLM-driven lint error autofix
at enterprise scale:
- Uses tree-sitter for context expansion (same as odin-lint)
- Generates search-and-replace patches via specially trained LLMs
- Re-runs the linter after each fix to verify (the denoising loop)
- 85% repair accuracy, 12,000+ issues automatically resolved
- The training approach: lint-error + context → correct patch JSONL

This is precisely the "Incremental Denoising" workflow in odin-lint V7.1 Section 13,
validated at industrial scale. The `run_lint_denoise` MCP tool (M5.6) is the
odin-lint implementation of the same idea.

**Semgrep Assistant:**
- AI triage for security findings: 96% agreement with human decisions
- AI-generated YAML rules from natural language descriptions
- "Assistant Memories": reusable triage decisions that improve future runs
- 6 million findings processed, 20% additional noise reduction beyond rules

The "memories" concept is relevant: if odin-lint tracked which C012 INFO
diagnostics a developer has consistently suppressed, it could learn not to fire
them again. This is a post-M6 idea but worth noting.

**DeepLint (2025, pre-launch):**
Cross-file semantic linting using LLMs: "understands what your code intends to do."
Pre-commit hook integration. Still in beta/waitlist as of April 2026. The concept
— using an LLM as the rule engine rather than pattern matching — is interesting but
the false-positive risk at current model reliability levels is high.

**Key lessons for odin-lint:**
- The BitsAI-Fix architecture (tree-sitter context + LLM patch + re-lint verify)
  is validated. The `run_lint_denoise` MCP tool (M5.6) should be designed with
  this paper's findings in mind.
- **Lint output format quality determines AI fix quality.** BitsAI-Fix depends on
  structured, machine-readable lint output (file, line, rule_id, message, fix_hint).
  odin-lint's `--format json` output (M4.1) is directly feeding this pipeline.
  The more precise the `fix_hint`, the better the AI patch.
- **Re-verification is mandatory.** Every AI fix system that works uses a
  lint-fix-re-lint loop. The `--fix` flag + exit code 0 re-verification is the
  correct design.

---

---

## Cross-Ecosystem Patterns Worth Adopting in odin-lint

This section distils the concrete, actionable patterns from the research above.
Each item is mapped to an existing odin-lint milestone or flagged as a new idea.

### Already in the Plan (Validated by Ecosystem Research)

| Pattern | Source | odin-lint mapping |
|---------|--------|-------------------|
| SARIF output format | All ecosystems | M4.1 `--format sarif` ✓ |
| Inline suppression comments | Ruff, ESLint | `// odin-lint:ignore C001` ✓ |
| Rule code taxonomy (C0XX/C1XX) | Ruff (E/W/F), Clippy (correctness/style) | Current taxonomy ✓ |
| Autofix as first-class feature | Clippy `--fix`, Ruff, Biome | M4.5 FixEdit ✓ |
| Lint-fix-re-lint denoising loop | BitsAI-Fix, Semgrep | `run_lint_denoise` MCP (M5.6) ✓ |
| Structured JSON output for AI | BitsAI-Fix dependency | `--format json` (M4.1) ✓ |
| Tree-sitter as shared parser foundation | OXC, BitsAI-Fix, Semgrep | tree-sitter CLI path ✓ |
| Config file for rule customisation | All tools | `odin-lint.toml` (M4+) ✓ |
| Version-gated migration rules | Clippy MSRV, Go `modernize` | C009/C010 (M3.4) ✓ |
| Cross-file analysis via call graph | Semgrep Pro, CodeGraph | DNA export + M5.6 ✓ |

### New Ideas to Evaluate (Not Yet in Plan)

**Idea 1 — Lightweight type model for early type-aware rules**

Biome v2 proved you can build type-aware rules without invoking the full compiler.
For odin-lint, a narrow type resolver that handles only the most common cases:
- Is this variable of type `mem.Allocator`? (for C012-T1)
- Is this variable of type `mem.Arena`? (for C012-T2)

This would not require full type inference — just resolving declared type
identifiers against known stdlib type names. Potentially achievable in M4 or M4.5,
removing the M6 dependency for C012-T1/T2.

*Assessment: Medium effort, high value. Would accelerate C012 Phase 2.*
*Recommended action: Add as a stretch goal to M4.5.*

---

**Idea 2 — MSRV-equivalent: odin-lint target version in config**

Clippy's MSRV feature means lints that suggest features not available in your
target Rust version are silenced. Odin equivalent: if a project targets an older
Odin build (pre-2026-04), C010 (Small_Array) should not fire because the new
syntax is not available.

```toml
[target]
odin_version = "dev-2026-01"   # C010 silent: [dynamic; N]T not yet available
```

*Assessment: Low effort, high user value. Prevents noise for users not yet on
latest Odin. Recommended for M4.0 alongside other config work.*

---

**Idea 3 — `modernize` as a first-class lint tier**

Go's `modernize` linter and Clippy's `restriction` category are both dedicated to
"flag old patterns regardless of correctness." odin-lint's C009/C010 are this
already. Making it a formal tier (`MIGRATION` alongside `correctness` and `style`)
signals to users that these rules are about upgrading, not fixing bugs.

```odin
DiagnosticType :: enum {
    NONE,
    VIOLATION,      // correctness — must fix
    CONTEXTUAL,     // style — should fix
    MIGRATION,      // modernise — upgrade when ready  ← NEW
    INTERNAL_ERROR,
    INFO,
}
```

*Assessment: Trivial to add. Recommended for M3.4 alongside C009/C010.*

---

**Idea 4 — Plug-in architecture for domain-specific rules**

golangci-lint's aggregator model lets domain experts write their own linters.
Go SQL teams wrote `unqueryvet`. Linux kernel teams wrote `klint`.
odin-lint's `plugin_main.odin` is already the seed of this.

For Odin specifically: a game developer could write a "hot path allocation" linter.
A networking developer could write an "arena usage" linter. The plugin system
makes odin-lint the platform rather than just a tool.

*Assessment: Architecture already partially in place. Full plugin API spec is
a post-M5 effort. Add to Future Vision section of V7 plan.*

---

**Idea 5 — `--watch` mode for interactive denoising**

Ruff has `--watch`, which re-lints on file save. Combined with the denoising
loop, this enables real-time "lint as you type" feedback without the full LSP.
Useful before OLS integration is complete (M5).

*Assessment: Low effort (file watcher + re-run). Valuable for developers not using
OLS. Recommended as an M4.0 addition: `odin-lint --watch ./src/`*

---

### Cross-Ecosystem Architecture Summary

The converging best-practice architecture across all ecosystems in 2026 is:

```
┌─────────────────────────────────────────────────────────────────┐
│  Single fast parser (tree-sitter or equivalent)                  │
│  ↓                                                               │
│  Multiple rule passes on the same parse tree (no re-parsing)    │
│  ↓                                                               │
│  Optional lightweight type model (no full compiler needed)       │
│  ↓                                                               │
│  Structured output: JSON + SARIF                                 │
│  ↓                                                               │
│  Autofix layer: machine-applicable edits as first-class output   │
│  ↓                                                               │
│  AI layer: lint output as structured signal → LLM patch gen      │
│  ↓                                                               │
│  Re-lint verification: every AI fix is verified by re-running    │
└─────────────────────────────────────────────────────────────────┘
```

odin-lint V7.2 implements every layer of this stack. The tree-sitter parser is
done. Rule passes are done. Structured JSON output is M4.1. Autofix is M4.5.
The AI layer (DNA export + `run_lint_denoise`) is M5.6. Re-lint verification
is built into the denoising loop design.

The only gap versus the best-in-class tools is the lightweight type model —
which Biome v2 proves is achievable without the full compiler. This is the one
area where odin-lint could accelerate ahead of its current M6 plan.

---

## References

- Ruff: https://astral.sh/ruff — Python linter, Rust-based, 500+ rules
- Ruff v0.15.0: https://astral.sh/blog/ruff-v0.15.0 (Feb 2026)
- `ty`: https://astral.sh/ty — Python type checker (Dec 2025)
- Biome v2: https://biomejs.dev — JS/TS all-in-one linter+formatter (June 2025)
- Oxlint v1.0: https://oxc.rs/docs/guide/usage/linter.html (June 2025)
- golangci-lint changelog: https://golangci-lint.run/docs/product/changelog/
- Clippy feature freeze: https://blog.rust-lang.org/inside-rust/2025/06/21/announcing-the-clippy-feature-freeze
- SpotBugs 4.9.8: https://github.com/spotbugs/spotbugs (Oct 2025)
- Semgrep cross-file analysis: https://semgrep.dev/docs/semgrep-code/semgrep-pro-engine-examples
- BitsAI-Fix paper: https://arxiv.org/abs/2508.03487 (Aug 2025)
- OpenGrep fork: https://github.com/opengrep/opengrep (Jan 2025)
- CodeGraph: https://github.com/colbymchenry/codegraph (tree-sitter + SQLite + MCP reference)

---

*Document status: Research complete — April 2026*
*Next review: When M4 is complete or a major new tool is released*
*Owner: plans/odin-lint-implementation-planV7.md*
