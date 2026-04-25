# olt — Implementation Plan V8
*Odin Language Tools — Version 0.8 → 1.0-alpha*
*April 2026 · Post-V7 Stabilisation + Rule Addendum + Product Readiness*

---

## 1. V7 History (Decisions & Steps)

V7 established the full foundation in one sustained sprint (April 12–25 2026).
Key architectural decisions that constrain and enable V8:

| Decision | Rationale | Impact on V8 |
|----------|-----------|--------------|
| tree-sitter for AST, OLS AST walker for C001/C101 | Two-strategy: SCM for new rules, AST walker for legacy | New rules use SCM; C032/C029 can use either |
| SCM queries embedded at compile-time (`#load`) | Self-contained binary, no install-time deps | All new rules get `.scm` files |
| SQLite graph DB (`.codegraph/olt_graph.db`) | Incremental, SQL-queryable, FTS5 | C029/C033 use graph return_type; P001/P002 need it |
| MCP server (`olt-mcp`) over stdio JSON-RPC | Zero Node.js, pure Odin | New rules automatically available via MCP |
| LSP proxy (`olt-lsp`) wrapping vanilla OLS | No fork maintenance | `--init` must set up OLS path |
| `olt.toml` / `odin-lint.toml` fallback | Smooth migration | V8 TOML additions follow existing section pattern |
| C001 ownership hints (INFO vs VIOLATION) | Reduce false positives, preserve signal | C032/C029 follow the same INFO/VIOLATION tiering |

### V7 Milestone Sequence (complete)
```
M0–M5.6  Foundation → OLS plugin → MCP → DNA graph   ✅
M6–M6.9  Extended rules C014–C020, B001–B003, C001 FP  ✅
M7       Graph enrichment: FTS5, enum members, Pass 4  ✅
M7.1     OLS refactoring: C012-T, rename_symbol, C101  ✅
M8       Frejay/Agent API: errorClass, lint_workspace   ✅
M9       [tools] TOML, TypeResolveContext, C201         ✅
M10      C203 defer scope trap                          ✅
M11      olt-lsp proxy, enum graph, C202 switch exhaust ✅
M12      C019 Phase 2, C012-T2, stabilisation review   ✅
RENAME   odin-lint → olt, v0.8.0, olt.toml             ✅
```

---

## 2. Current State Assessment — 0.8

**What we have:**
- 22 rules (C001–C203, B001–B003) with 87 unit tests, all passing
- Graph DB: FTS5 search, enum members, call graph, memory roles
- Three binaries: `olt` (CLI), `olt-mcp` (AI agents), `olt-lsp` (editor proxy)
- Own codebase: 0 violations; Odin core: 0 C001/C002; RuiShin: stable baseline
- Review: all 15 memory/threading/JSON findings fixed

**What's missing for 1.0-alpha:**
- First-run experience (`--init` onboarding)
- System install (`--install` / softlink)
- Top Odin-specific and Go→Odin trap rules from addendum (esp. C032)
- Linux ARM build
- Public-facing README/docs

---

## 3. Pending Product Items

### P-A — `olt --init` (Onboarding)

Interactive first-run wizard. Three phases:

**Phase 1 — OLS check**
```
Checking for OLS...  ✅ /usr/local/bin/ols  |  ❌ not found
  [1] Enter path   [2] Download & build from github.com/DanielGavin/ols   [3] Skip
```
Shell out to `git clone` + `./build.sh` for option 2. Write `ols_path` to `olt.toml`.

**Phase 2 — Config file**
```
No olt.toml found. Create one? [Y/n]
  Location: [1] ./olt.toml  [2] ~/.config/olt/olt.toml
  Profile:  [1] basic  [2] standard (recommended)  [3] full
```
"standard" = all correctness + style + C029/C032/C033 (stdlib_safety).

**Phase 3 — Install** (see P-B)

Implementation: new `src/core/init.odin`, new `_init_command` in `main.odin`.
Uses `os.stdin` readline for prompts.

### P-B — `olt --install` (System Install)

Creates symlinks for `olt`, `olt-mcp`, `olt-lsp`:
- macOS / Linux default: `~/.local/bin/` (no sudo, usually in PATH)
- Optional: `/usr/local/bin/` (prompts for sudo)
- Checks if target dir is in PATH; warns if not

### P-C — Linux ARM64 Build

Build on this machine (Apple M-series) using Podman Linux ARM64 container:
```bash
podman run --platform linux/arm64 -v $(pwd):/build ubuntu:24.04 \
  bash /build/scripts/build_linux.sh
```
Requires: cross-compiling the C libraries (tree-sitter, SQLite) for Linux ARM64.
`scripts/build_linux.sh` — new script; compiles C deps + Odin binaries inside container.

---

## 4. New Rules — Addendum Analysis & Priority

Rules from `POST-V7-RULE-ADDENDUM.md`, ordered by implementation priority.

### Tier 1 — Immediate (M13): Low cost, critical value

**C032 — defer Inside For Loop** ★ HIGHEST PRIORITY
- Odin-unique bug: defer scopes to procedure, not loop body → memory leaks silently on each iteration
- Compiler does NOT catch. Runtime: silent leak until OOM.
- Detection: SCM — `defer_statement` direct child of `for_statement` block
- Escape hatch: suppress if deferred var declared outside the loop (e.g. `defer wg.done()`)
- Tier: VIOLATION, on by default
- Fixtures: ready in addendum

**C025 — `append(slice, v)` Without Address-Of**
- Go habit: `append(s, v)` vs Odin: `append(&s, v)` — silent wrong behaviour
- Auto-fix: prepend `&` to first argument
- SCM: `call_expression` with function=`append`, first arg is identifier (not address-of)

**C021 — Go-Style `fmt.*` Calls**
- `fmt.Println`, `fmt.Printf`, `fmt.Sprintf` etc. — compile errors with confusing messages
- Auto-fix map: `fmt.Println` → `fmt.println`, `fmt.Printf` → `fmt.printf`
- `fmt.Sprintf` → suggest `fmt.tprintf` (temp) or `fmt.aprintf` (owned)
- SCM: selector_expression with pkg=`fmt` and known Go func names

**C022 — Go-Style Range Loop**
- `for i, v := range slice` → Odin: `for v, i in slice` (reversed order)
- Auto-fix applicable
- SCM: detect `range` keyword in for-statement header

**C023 — C-Style Pointer Dereference**
- `*ptr` → Odin: `ptr^`
- Auto-fix: `*name` → `name^`
- SCM: unary_expression with operator `*`

### Tier 2 — Stdlib Safety (M14): Extends existing infrastructure

**C029 — stdlib Allocating Procs Not Freed**
- Natural extension of C001 to known stdlib allocators: `strings.split`, `strings.clone`, `strings.join`, `fmt.aprintf`, `os.read_entire_file`, etc.
- Full list in addendum Appendix A
- Implementation: extend `memory_safety.scm` OR add new `stdlib_allocs.scm`
- Same C001 escape hatches: `defer delete(@var)` or `return @var`
- Enabled via `[domains] stdlib_safety = true` in `olt.toml`

**C033 — `strings.Builder` Not Destroyed**
- `strings.builder_make()` → must `defer strings.builder_destroy(&b)`
- Same pattern as C029, same infrastructure
- Bundled under `stdlib_safety` domain

**C028 — `fmt.tprintf` Result Stored Past Temp Scope**
- `tprintf` allocates on temp_allocator; storing in struct field or returning creates dangling ref
- Detection: tprintf result assigned to var → var assigned to field or returned
- Tier: CONTEXTUAL (not all cases are bugs — e.g. immediate use)
- Bundled under `stdlib_safety` domain
- New TOML domain: `[domains] stdlib_safety = true`

### Tier 3 — Semantic / Medium Priority (M15 or post-alpha)

**C031 — `panic` for Expected Runtime Failures** (INFO)
- `if !ok { panic("file not found") }` → should return error instead
- SCM: `if !ok { panic(...) }` pattern
- Tier: INFO — not all panics-on-!ok are wrong (tests, init code)

**C030 — `or_return` Outside Error-Returning Proc**
- Needs enclosing proc signature inspection (AST walk up to proc declaration)
- Medium cost: requires parsing proc return type from the AST
- Defer to after --init / install land

**C034 — Unused Index Blank in For Loop** (INFO, auto-fix)
- `for v, _ in collection` → `for v in collection`
- Low cost, low urgency. Auto-fix available.

**C037 — Trailing `return` in Void Proc** (INFO, auto-fix)
- Go habit; unnecessary in Odin
- SCM: last statement of void proc is `return_statement`
- Low urgency; INFO only

### Tier 4 — Compile-Error Catchers (lower priority)

**C024** — `errors` package import (doesn't exist in Odin) — compile error
**C026** — `go f()` goroutine syntax — compile error
**C027** — `make(chan T)` / `<-` channel syntax — compile error

These three are compile errors the user will discover immediately. The main value
is a better error message. Defer until after alpha if time allows.

### Tier 5 — Package Scope (post-alpha)

**P001** — Inconsistent error return convention within package
**P002** — Exported proc without doc comment (library mode)

Both require multi-file context (PackageContext). Infrastructure exists (M6.9).
Implement post-1.0-alpha.

---

## 5. TOML Schema Additions (V8)

```toml
# New in V8
[domains]
stdlib_safety = true    # C028, C029, C033 — stdlib memory mistakes
go_migration  = false   # C021–C025 — for teams migrating from Go/LLM output

[rules.C036]
enabled = false
min_size = 256          # flag allocation literals >= this value

[rules.P001]
enabled = false
min_procs = 3

[rules.P002]
enabled = false
```

---

## 6. Milestones → 1.0-alpha

```
Current:  olt 0.8.0  (April 25 2026)
         22 rules · graph · MCP · LSP proxy · tests passing

M13  Critical Odin Trap Rules              → 0.85
     C032 defer-in-loop (VIOLATION)
     C025 append without &  (VIOLATION + auto-fix)
     C021 Go fmt calls      (VIOLATION + partial auto-fix)
     C022 Go range loop     (VIOLATION + auto-fix)
     C023 C-style deref     (VIOLATION + auto-fix)
     Tests: 5 new rule test suites

M14  Stdlib Safety Domain                  → 0.90
     C029 strings.split + stdlib allocators
     C033 strings.Builder not destroyed
     C028 tprintf temp scope (CONTEXTUAL)
     New TOML domain: stdlib_safety = true
     Appendix A proc list wired into SCM query

M15  Product Readiness                     → 0.95
     olt --init  (P-A: OLS check, config creation, profile selection)
     olt --install  (P-B: system symlink)
     Version bump to 0.9.0

M16  1.0-alpha                             → 1.0-alpha
     Linux ARM64 build via Podman  (P-C)
     C031 panic-for-errors (INFO)
     C030 or_return signature check
     C034 unused blank index (INFO + auto-fix)
     C037 trailing void return (INFO + auto-fix)
     README / public docs
     Version bump to 1.0.0-alpha
```

### Post-Alpha (1.0 → 1.x)
```
  C024, C026, C027  compile-error catchers
  P001, P002        package-scope rules (library mode)
  Linux x86 build   (on external server)
  C036              magic allocation sizes (opt-in)
  GitHub Actions    self-hosted runners (macOS ARM + Linux x86)
```

---

## 7. Rule ID Registry (V8 additions)

| Rule | Group | Domain | Default | Tier |
|------|-------|--------|---------|------|
| C021 | Go-compat | go_migration | off | correctness |
| C022 | Go-compat | go_migration | off | correctness |
| C023 | Go-compat | go_migration | off | correctness |
| C024 | Go-compat | go_migration | off | correctness |
| C025 | Go-compat | on | **on** | correctness |
| C026 | Go-compat | go_migration | off | correctness |
| C027 | Go-compat | go_migration | off | correctness |
| C028 | Stdlib safety | stdlib_safety | **on** | correctness |
| C029 | Stdlib safety | stdlib_safety | **on** | correctness |
| C030 | Correctness | on | **on** | correctness |
| C031 | Correctness | on | off (INFO) | style |
| C032 | Correctness | on | **on** | correctness |
| C033 | Stdlib safety | stdlib_safety | **on** | correctness |
| C034 | Style | on | off (INFO) | style |
| C035 | → C202 already implemented | — | — | — |
| C036 | Style | opt-in | off | style |
| C037 | Style | on | off (INFO) | style |
| P001 | Package | library_mode | off | style |
| P002 | Package | library_mode | off | style |

C025 and C032 are **on by default** — they catch silent bugs that the compiler
misses and have near-zero false positive rate. All Go-compat rules (C021–C024,
C026–C027) are grouped under `go_migration` (off by default) because they
produce noise on pure Odin codebases.

---

## 8. Implementation Notes

### C032 Implementation Path
SCM query in `ffi/tree_sitter/queries/defer_in_loop.scm`:
```scheme
; defer statement as a direct child of a for-statement's body block
(for_statement
  body: (block
    (defer_statement) @defer_in_loop))
```
Escape hatch (Odin code): check that the deferred variable is NOT declared
inside the loop body (i.e. its declaration line is before the `for` statement).
`defer wg.done()` and `defer mutex.unlock()` — where the resource is external
— are legitimate and must not fire.

### C029 Implementation Path
Option A: New `stdlib_allocs.scm` query. Large but extensible.
Option B: Extend C001's `memory_safety.scm` with the proc list from Appendix A.
**Recommendation: Option A** — keep C001 and C029 cleanly separated; share
escape-hatch logic via a common `c001_c029_check_block` helper.

### C021–C023 Auto-Fix
The SCM queries for these rules capture exact replacement targets.
The existing `autofix.odin` FixEdit infrastructure handles the rewrites.
Auto-fix is safe (single identifier replacement) and should use `--fix` mode.

### --init Implementation
New file: `src/core/init.odin`
- `run_init() -> int` — called from `_main` when `--init` flag set
- Uses `os.stdin` for prompts: `fmt.print("..."); line, _ = bufio.reader_read_string(...)`
- Writes `olt.toml` via `os.write_entire_file`
- Shells out to `git clone` + `./build.sh` for OLS download option
- Calls `run_install()` at end (optional)

---

*V8 plan written April 25 2026*
*Source rules: plans/POST-V7-RULE-ADDENDUM.md*
*Prerequisite: olt 0.8.0 (RENAME milestone complete)*
