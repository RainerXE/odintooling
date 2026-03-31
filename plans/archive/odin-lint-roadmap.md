# odin-lint — Implementation Roadmap
*A Super Linter for the Odin Programming Language*
*Version 1.0 · 2025*

---

## Table of Contents
1. [Overview & Goals](#1-overview--goals)
2. [Architecture](#2-architecture)
3. [Milestones](#3-milestones)
   - [M0 — Foundation](#milestone-0--foundation--estimated-23-weeks)
   - [M1 — Correctness Tier](#milestone-1--correctness-tier-core-rules--estimated-46-weeks)
   - [M2 — Config + Suspicious/Style Tiers](#milestone-2--config--suspiciousstyle-tiers--estimated-34-weeks)
   - [M3 — OLS Integration + Auto-fix](#milestone-3--ols-integration--auto-fix--estimated-35-weeks)
   - [M4 — Perf Tier + GitHub Action + v1.0](#milestone-4--perf-tier--github-action--community-release--estimated-34-weeks)
4. [Risk Register](#4-risk-register)
5. [Summary Timeline](#5-summary-timeline)
6. [Definition of Done](#6-definition-of-done-for-each-rule)
7. [Community Integration](#7-community-integration)

---

## 1. Overview & Goals

`odin-lint` is a static analysis tool for the Odin programming language. Its purpose is to enforce correctness, idiomatic patterns, and performance best practices through configurable, tiered rules — without duplicating `odin fmt`, `odin build`, or the OLS language server.

### Design Philosophy

- **Correctness first** — only deny-by-default rules that have zero false positives
- **OLS-native** — surface diagnostics through the language server, not just CLI
- **Pluggable** — external rule packs via YAML/TOML without recompilation
- **Orthogonal** — never reimplement what `odin fmt`, `odin build`, or OLS already do
- **Incremental** — start with 15 rock-solid rules, grow with community feedback

### Lint Tier Model (inspired by Rust Clippy)

| Tier | Default | Examples | Rationale |
|------|---------|----------|-----------|
| `correctness` | deny | missing defer free, double-free pattern | Clear bugs, zero false positives |
| `suspicious` | warn | raw pointer overuse, unreachable branches | Likely wrong, might be intentional |
| `style` | allow (opt-in) | naming conventions, proc length | Idiomatic Odin preferences |
| `perf` | allow (opt-in) | cache-unfriendly layouts, needless alloc | Data-oriented design patterns |

---

## 2. Architecture

`odin-lint` is composed of four independently testable layers. Each layer has a clean interface so components can be replaced or extended without affecting others.

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| L1 — Parse | tree-sitter-odin (amaanq fork) | Produce AST from source files |
| L2 — Analyse | Rule Engine (`core/`) | Walk AST, apply rule matchers |
| L3 — Report | Formatter (`output/`) | Emit diagnostics: CLI, JSON, LSP |
| L4 — Integrate | OLS plugin + CI action | Surface warnings in editors and pipelines |

### Directory Structure

```
odin-lint/
├── core/              # Rule engine: AST walker + rule registry
├── rules/
│   ├── correctness/   # Tier 1: deny-by-default
│   ├── suspicious/    # Tier 2: warn-by-default
│   ├── style/         # Tier 3: opt-in
│   └── perf/          # Tier 4: opt-in
├── output/            # CLI, JSON, LSP diagnostic formatters
├── integrations/
│   ├── ols/           # OLS (language server) plugin
│   └── github-action/ # CI integration
├── tests/
│   ├── fixtures/      # .odin files: should_pass / should_fail
│   └── snapshots/     # Expected diagnostic output
└── docs/              # Rule documentation (one .md per rule)
```

---

## 3. Milestones

The roadmap is divided into five milestones. Each milestone ends with a **gate** — a set of pass/fail criteria that must be met before work begins on the next milestone.

---

### 🏁 MILESTONE 0 · Foundation · Estimated: 2–3 weeks

**Goal:** A working skeleton — parse an Odin file, walk its AST, emit one diagnostic. No rules, no config, no integrations. Prove the pipeline works end to end.

#### Tasks

- Set up repo: directory structure, README, MIT licence, CI skeleton (GitHub Actions)
- Choose and pin tree-sitter-odin fork (recommend `amaanq/tree-sitter-odin` — most active)
- Write an AST walker that visits every node in a file
- Implement the diagnostic struct: `{ file, line, col, rule_id, tier, message, fix? }`
- Write a stub rule: warn on any procedure named `TODO_FIXME` (purely for pipeline validation)
- CLI: `odin-lint <file>` prints diagnostics to stdout
- Test harness: fixture files in `tests/fixtures/pass/` and `tests/fixtures/fail/`, runner compares output to snapshots

#### Tests for M0

| Test | Pass Condition |
|------|----------------|
| AST walker visits all nodes | Node count matches expected count for each fixture file |
| Stub rule fires correctly | Exactly one diagnostic emitted for fixture with `TODO_FIXME` proc |
| Clean file produces zero output | Empty stdout on a known-good `.odin` file |
| CLI exit codes | Exit 0 on clean, exit 1 on any correctness finding |
| Snapshot test runner works | CI fails if snapshot differs from actual output |

> **🔒 GATE 0 — Must pass all 5 tests above before starting M1**

---

### 🏁 MILESTONE 1 · Correctness Tier (Core Rules) · Estimated: 4–6 weeks

**Goal:** Ship the `correctness` rule tier — rules that are deny-by-default and must have zero false positives. These form the trust foundation of the tool. If any of these fire incorrectly, the whole tool loses credibility.

#### Target Rules (Correctness Tier — 8 rules)

| Rule ID | Pattern Detected | Source Inspiration |
|---------|-----------------|-------------------|
| C001 | Allocation without matching `defer free` in same scope | Rust: `clippy::mem_forget` |
| C002 | `defer free` on wrong pointer (double-free risk) | C: AddressSanitizer |
| C003 | `context.allocator` swapped inside a proc but not restored | Odin-specific |
| C004 | Unreachable code after `return` / `break` | Java: FindBugs `UC_USELESS_CONDITION` |
| C005 | Shadowed variable silently overrides outer binding | Rust: `clippy::shadow_reuse` |
| C006 | Loop variable captured in closure/proc literal | Go vet: `loopclosure` |
| C007 | Integer cast narrowing without explicit check | Zig: integer overflow safety |
| C008 | Slice bounds not validated before index | Odin-specific runtime safety |

#### Tasks

- Implement rule registry: rules self-register, engine iterates all active rules per AST node
- Implement each rule as a separate file in `rules/correctness/` with: `matcher()`, `message()`, `fix_hint()`
- Write at least 3 fixture pairs (pass + fail) per rule = 48 fixture files minimum
- Add `--rule=C001` flag to run a single rule (crucial for debugging)
- Add `--fix` flag that prints fix hints (no auto-apply yet)
- Write rule documentation: `docs/correctness/C001.md` … `C008.md` (one per rule)

#### Tests for M1

| Test | Pass Condition |
|------|----------------|
| Zero false positives | All `pass/` fixtures produce zero diagnostics for all 8 rules |
| All true positives fire | All `fail/` fixtures produce exactly the documented diagnostic |
| Rule isolation | Disabling a rule via config produces no output for its fixtures |
| Fix hints present | `--fix` flag produces a non-empty hint for every correctness rule |
| Snapshot stability | Re-running on unchanged files produces byte-identical output |
| No rule duplicates `odin build` | Run `odin build` on every fixture; no rule fires on errors the compiler already catches |

> **🔒 GATE 1 — Zero false positives on correctness tier. 100% fixture coverage. No duplication of compiler errors.**

---

### 🏁 MILESTONE 2 · Config + Suspicious/Style Tiers · Estimated: 3–4 weeks

**Goal:** Make the tool configurable and add the two opt-in tiers. Users can now tailor `odin-lint` to their project's standards via an `odin-lint.toml` config file.

#### Config File Design

```toml
# odin-lint.toml
[lint]
tiers = ["correctness", "suspicious"]  # enabled tiers

[rules]
C003.severity = "warn"   # downgrade a correctness rule
S012.enabled  = false    # disable a style rule

[paths]
exclude = ["vendor/", "generated/"]
```

#### Target Rules (Suspicious — 5 rules, Style — 4 rules)

| Rule ID | Tier | Pattern | Notes |
|---------|------|---------|-------|
| S001 | suspicious | Raw pointer `[]^T` where `[]T` would suffice | Common Odin newcomer mistake |
| S002 | suspicious | Empty `when` branch in `switch` | Usually a logic error |
| S003 | suspicious | Proc with >5 return values | Suggests struct refactor needed |
| S004 | suspicious | Allocator passed as param but never used | Dead parameter |
| S005 | suspicious | Boolean param that controls fundamentally different paths | Clippy: `fn_bool_param` |
| T001 | style | Proc name does not follow `snake_case` | Odin convention |
| T002 | style | Type name does not follow `PascalCase` | Odin convention |
| T003 | style | Proc body exceeds 80 lines | Complexity threshold |
| T004 | style | Magic number (untyped integer literal not 0/1) | Readability |

#### Tasks

- Config parser: read `odin-lint.toml`, merge with CLI flags (CLI overrides file)
- Implement 5 suspicious + 4 style rules with full fixture coverage
- `--explain <rule_id>` flag: prints full description + example + fix hint
- JSON output mode: `--format=json` for CI integration
- Path exclusion logic from config

#### Tests for M2

| Test | Pass Condition |
|------|----------------|
| Config loading | All TOML fields parse correctly; malformed TOML exits with clear error |
| Style tier disabled by default | Style rules produce no output unless explicitly enabled |
| Rule downgrade via config | C003 set to `warn` does not cause non-zero exit code |
| Path exclusion | Files matching `exclude` patterns produce zero diagnostics |
| JSON output is valid | JSON schema validated by fixture runner on all outputs |
| `--explain` completeness | Every rule has a non-empty `--explain` entry |

> **🔒 GATE 2 — Config parser fully tested. Style tier off by default and verifiably so. JSON output valid against schema.**

---

### 🏁 MILESTONE 3 · OLS Integration + Auto-fix · Estimated: 3–5 weeks

**Goal:** Diagnostics appear inline in VS Code and Neovim via OLS. Selected rules gain auto-fix capability. This is the milestone that makes `odin-lint` feel like a first-class development tool rather than a CLI script.

#### OLS Integration Approach

OLS supports custom diagnostic providers via its plugin system. `odin-lint` will run as a subprocess that OLS spawns, communicating over stdin/stdout using a minimal JSON protocol mirroring LSP's `PublishDiagnostics` format.

- `odin-lint --lsp-mode`: runs in long-lived subprocess mode, reads file change events from stdin, emits diagnostic JSON to stdout
- OLS plugin (`integrations/ols/`): configures OLS to spawn `odin-lint` and forward its diagnostics
- Diagnostic severity maps: `correctness` → Error, `suspicious` → Warning, `style`/`perf` → Hint
- Code actions: for rules with fix hints, expose an LSP code action (quick fix) in the editor

#### Auto-fix Rules (Phase 1 — safe transformations only)

| Rule | Before | After (auto-fix) |
|------|--------|------------------|
| C001 | `buf := make([]u8, 1024)` | `buf := make([]u8, 1024)` + `defer delete(buf)` inserted on next line |
| T001 | `proc MyProc() {}` | `proc my_proc() {}` |
| T002 | `my_type :: struct {}` | `My_Type :: struct {}` |
| C004 | `return x` followed by unreachable `foo()` | Dead code removed |

#### Tasks

- Implement `--lsp-mode` with JSON diagnostic protocol
- Write and publish OLS plugin configuration (`integrations/ols/README.md` + config snippet)
- Test OLS integration in VS Code (odin-lsp extension) and Neovim (nvim-lspconfig)
- Implement `--fix --apply` flag: modifies files in-place with confirmation prompt
- Fix safety: never apply a fix that changes semantics — fixable rules have an explicit `safe_fix = true` marker
- Add `odin-lint check` command: like `lint` but exits 0 if only style/perf findings (useful for CI gates)

#### Tests for M3

| Test | Pass Condition |
|------|----------------|
| LSP mode starts and stays alive | Process remains running after 100 sequential file-change events |
| Diagnostic positions are correct | Line/col in LSP output matches the actual problematic token |
| Auto-fix round-trips cleanly | Apply fix → re-lint → zero findings for that rule on same file |
| Fix does not corrupt files | `odin build` passes on all auto-fixed fixtures |
| VS Code integration smoke test | Opening a `fail/` fixture shows red/yellow squiggles at correct positions |
| No fix applied without `--apply` | `--fix` alone only prints diff, does not modify files on disk |

> **🔒 GATE 3 — OLS integration smoke-tested in at least 2 editors. Auto-fix round-trip passes for all 4 rules. No file corruption.**

---

### 🏁 MILESTONE 4 · Perf Tier + GitHub Action + Community Release · Estimated: 3–4 weeks

**Goal:** Add the performance/data-oriented rules, publish a GitHub Action, and release v1.0 publicly with full documentation.

#### Target Rules (Performance Tier — 4 rules)

| Rule ID | Pattern | Why It Matters for Odin |
|---------|---------|------------------------|
| P001 | Struct fields ordered suboptimally (padding waste) | Odin's target audience does low-level, cache-sensitive code |
| P002 | AOS layout where SOA would be cache-friendlier | Core data-oriented design pattern — unique to Odin tooling |
| P003 | Allocation inside a hot loop | `make`/`new` inside `for` loop without pool/arena |
| P004 | `context.temp_allocator` used outside a temp scope | Temp allocator leaks if `free_all` not called correctly |

#### GitHub Action

```yaml
# .github/workflows/lint.yml
- uses: odin-lang/odin-lint-action@v1
  with:
    tiers: correctness,suspicious
    fail-on: correctness
```

#### Documentation Requirements for v1.0

- `README.md`: install, quick start, config reference
- Rule catalogue: one page per rule (rule ID, description, bad example, good example, fix hint, rationale)
- Contributing guide: how to write a new rule (template + checklist)
- `CHANGELOG.md` with semantic versioning from v0.1 onward
- Integration guide: VS Code, Neovim, Helix, CI

#### Tests for M4

| Test | Pass Condition |
|------|----------------|
| P001–P004 fixture coverage | 3 pass + 3 fail fixtures per rule, all passing |
| GitHub Action end-to-end | Action runs on a test repo, fails on correctness finding, passes on clean repo |
| Documentation completeness | Every rule ID has a matching `docs/` entry; CI enforces this |
| Install test | Fresh install on Linux, macOS, Windows (WSL) and run `odin-lint --version` |
| Performance benchmark | `odin-lint` on the Odin standard library source completes in under 5 seconds |
| No regression on prior milestones | Full test suite (all milestones) passes green |

> **🔒 GATE 4 (v1.0 Release Gate) — Full test suite green. Docs complete. GitHub Action published. Perf benchmark under 5s on stdlib.**

---

## 4. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `tree-sitter-odin` fork diverges or goes unmaintained | Medium | Blocks all AST work | Pin to a specific commit hash; contribute upstream; keep parser adapter isolated behind an interface so it can be swapped |
| Odin language changes break AST assumptions | Low (language is stable) | Rule rewrites needed | Monitor `odin-lang/Odin` releases; add a nightly CI run against latest Odin |
| Correctness rules produce false positives post-release | Medium | Loss of user trust | Strict Gate 1 process; public rule disable mechanism; fast patch release process (< 48h) |
| OLS plugin API changes | Medium | M3 rework needed | Keep LSP mode self-contained; document the protocol so it works with other editors too |
| Low community adoption | Medium | Reduces feedback quality | Announce on Odin Discord early (even at M1); invite rule contributions before v1.0; keep install dead-simple |

---

## 5. Summary Timeline

| Milestone | Focus | Duration | Exit Gate |
|-----------|-------|----------|-----------|
| M0 | Foundation: pipeline + AST walker | 2–3 weeks | 5 pipeline tests pass |
| M1 | Correctness tier (8 rules) | 4–6 weeks | Zero false positives, full fixture coverage |
| M2 | Config + Suspicious/Style tiers | 3–4 weeks | Config tested, style off by default |
| M3 | OLS integration + auto-fix | 3–5 weeks | 2-editor smoke test, fix round-trip |
| M4 | Perf tier + GH Action + v1.0 | 3–4 weeks | Full suite green, docs complete, <5s bench |
| **Total** | | **15–22 weeks** | **v1.0 public release** |

---

## 6. Definition of Done (for each Rule)

Every rule — regardless of tier — must satisfy **all** of the following before it is merged:

- [ ] **Rule file**: `rules/<tier>/<ID>.odin` with `matcher()`, `message()`, and `fix_hint()` implemented
- [ ] **Documentation**: `docs/<tier>/<ID>.md` with description, bad example, good example, rationale, and inspiration source
- [ ] **Fixtures**: minimum 3 `pass/` and 3 `fail/` `.odin` files covering edge cases
- [ ] **Snapshot**: expected diagnostic output committed and verified by CI
- [ ] **Orthogonality check**: manually confirmed that `odin build` does NOT already report this error
- [ ] **False positive review**: at least 50 lines of real-world Odin code (from `odin-lang/Odin` stdlib) tested with no spurious firing
- [ ] **`--explain` entry**: non-empty output for `odin-lint --explain <ID>`

---

## 7. Community Integration

`odin-lint` is most valuable if the community contributes rules. The rule system is designed for this from day one.

- **Announce at M1** on the Odin Discord (`#tooling` channel) — invite early adopters and false-positive reports
- **Rule proposal template**: GitHub issue template for new rule requests (tier, pattern, rationale, example)
- **Rule bounties**: tag `help wanted` rules with estimated effort (S/M/L)
- **Integration request tracker**: track editor integration requests — prioritise editors with active Odin communities
- **Versioned rule sets**: allow projects to pin to a rule set version so upgrades don't break CI unexpectedly

---

*odin-lint Roadmap v1.0 · Built for the Odin community*
