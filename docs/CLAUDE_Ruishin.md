# RuiShin — Claude Project Instructions

## Reference Documents

Read these files when starting a new session or when working in the relevant domain:

- [ARCHITECTURE_GUIDELINES21.md](ARCHITECTURE_GUIDELINES21.md) — system-wide architecture principles and constraints
- [MEMORY_ARCHITECTURE.md](MEMORY_ARCHITECTURE.md) — memory/resource architecture patterns
- [ODIN_STYLE_GUIDE_v2.md](ODIN_STYLE_GUIDE_v2.md) — Odin language style conventions to follow in all code

## Plans & Memory

- [ai-memory/](ai-memory/) — long-term, higher-level goals and strategic plans; consult for direction and intent
- [plans/](plans/) — short-term implementation plans for current or recent work; consult before starting any task

## Project Overview

2D rendering engine demo app written in the Odin programming language.
GPU backend: Sokol GFX (`sg.*`).
UI layout: Clay.
Deferred command-buffer system (Phase F.3): `Draw_List` records `Draw_Command` variants per `Draw_Layer`, replayed at flush.

Draw layer order: `.Offscreen` → `.Background` → `.Content` → `.Overlay`

## Build

Primary command (works from project root or build directory):
```sh
odin run build/build.odin -file          # release (default)
BUILD_MODE=debug odin run build/build.odin -file          # debug build
STATIC_BUILD=true odin run build/build.odin -file         # static linking
STATIC_BUILD=true BUILD_MISSING_STATIC_LIBS=true odin run build/build.odin -file  # fully static
bash scripts/build-check.sh              # quick validation
```

Collections: `vendor-local=vendor-local`, `project=src`, `configpkg=src/configpkg`
Output: `artifacts/ruishin_demo_macARM`
Platforms: macOS (darwin/darwinARM), Linux (linux/linuxARM), Windows — x86/AMD64 + ARM64

## Key Architecture

### Flush Pipeline

- `g2d_flush_gpu_pre_pass()` → processes draw list → uploads vertices via `sg.append_buffer()` → `_g2d_flush_offscreen_passes()` → pending blurs
- `g2d_end_frame()` → renders screen batches inside active Sokol pass → calls `draw_list_clear()`
- `_g2d_flush_offscreen_passes()` does NOT check `b.flushed` — re-renders all non-nil-target batches

### Shadow Cache

- `map[Shadow_Key]^Shadow_Cache_Entry` in `ctx.shadow_cache` — NOT cleared per frame
- Each unique shadow shape gets its own offscreen RT (shadow RT + temp RT for blur)
- **CRITICAL**: Do NOT use `draw_list_push(Cmd_Shadow_Silhouette)` for cache-miss — Odin `for x in dynamic_arr` snaps slice length at loop start; commands appended during iteration are never seen in the same frame
- Cache-miss fix: render silhouette directly into `entry.rt_shadow` by temporarily swapping `ctx.active_rt`

### Shadow Fix Pattern (g2d_core.odin)

```odin
old_rt := ctx.active_rt
old_matrix := ctx.curr_matrix
old_scissor_on := ctx.curr_scissor_on
old_scissor := ctx.curr_scissor
old_opacity := ctx.curr_opacity
ctx.active_rt = &entry.rt_shadow
ctx.curr_matrix = linalg.MATRIX3F32_IDENTITY
ctx.curr_opacity = 1.0
ctx.curr_scissor_on = true
ctx.curr_scissor = [4]f32{0, 0, f32(entry.rt_shadow.width), f32(entry.rt_shadow.height)}
g2d_fill_rect_rounded_immediate(blur*2, blur*2, w, h, radius, renderer.paint_solid(color))
ctx.active_rt = old_rt
// restore other state...
```

## Project Folders

### [src/logging/](src/logging/)
Full structured logging system (v2.1). Key files:
- `logging_config.odin` — defines all log categories/levels (single source of truth)
- `logging_setup.odin` — decides which categories are active at runtime
- `logging.odin` — public API (`logging.debug(...)`, `logging.info(...)`, etc.)
- `README_LOGGING.md` — usage guide; `migration_guide.md` — migration from older versions

Usage pattern: call `logging.init_default()` in `main.odin`; enable only what you need. Never configure logging inline in feature code.

### [tests/](tests/)
Test suite following Odin's official testing guidelines. Structure:
- `tests/unit/` — unit tests per module (graphics, engine, ui, renderer)
- `tests/integration/` — integration tests
- `tests/performance/` — performance/stress tests
- `tests/rsd/` — RSD format tests
- `TESTING_README.md` — full test system documentation

### [build/](build/)
Central build system. Single source of truth for all build configuration.
- `build.odin` — main build script (run with `odin run build.odin -file`)
- `odin.json` — Odin project configuration
- `ols.json` — OLS language server configuration
- `BUILD-README.md` — full build system documentation
- `artifacts/` — compiled output (`ruishin_demo_macARM`)

## Key File Paths

| File | Purpose |
|------|---------|
| [src/main.odin](src/main.odin) | App entry; `frame` proc contains render loop |
| [src/graphics/g2d_core.odin](src/graphics/g2d_core.odin) | 2D renderer core; shadow functions ~L4660–4855 |
| [src/graphics/g2d_offscreen.odin](src/graphics/g2d_offscreen.odin) | `_g2d_flush_offscreen_passes()` |
| [src/renderer/draw_list.odin](src/renderer/draw_list.odin) | `Draw_List`, `Draw_Command`, `Draw_Layer` |

## Naming Conventions

| Scope | Criteria | Style | Marker |
|-------|----------|-------|--------|
| Private | Module-internal only | `snake_case` | `@private` |
| Internal | Used inside defining package only | `snake_case` | — |
| Public | Used outside defining package | `camelCase` | — |

## Logging Rules

- **Never use `fmt.printf` or similar for logging** — all output must go through `src/logging/logging.odin`
- All logging must be guarded by `#config` flags (compile-time)
- Default/release build: minimal logging only (`logging.init_default()`)
- Debug builds: enable via `-define:DEBUG=true`; use `logging.debug()` with appropriate tags
- Runtime info: use `logging.info()` with tag-based control
- All log files (runtime and debug) written to `artifacts/logs/` — already covered by `artifacts/.gitignore`, never committed
- Never configure logging inline in feature code — only in `main.odin` or `logging_setup.odin`

## Testing Requirements

- Write unit tests for all new public API functions in [tests/unit/](tests/unit/)
- Add integration tests for new features in [tests/integration/](tests/integration/)
- Coverage targets: unit ≥80%, integration ≥70%, overall ≥75%
- Test edge cases and error conditions
- Verify no regressions in existing tests before committing

## Workflow Rules

- **Always check plans before implementing** — before starting any implementation task, look in [plans/](plans/) for a relevant plan file. If a matching plan exists, read it fully and follow it. For broader context or direction, also check [ai-memory/](ai-memory/).
- **Create a plan file for every non-trivial task** — create a plan in [plans/](plans/) named `YYMMDD-short-description.md` (e.g. `260311-fix-F3_problem2.md`). Keep it continuously updated as work progresses — check off completed steps, note findings, and record decisions. When the task is fully complete, rename the file to `OK_YYMMDD-short-description.md`.
- **Verify build before committing** — run `bash scripts/build-check.sh` before every commit; run `git diff` to review all changes first.
- **Never use git worktrees** — use plain branches only (`git checkout -b branch-name`). Worktrees break other tools (git GUIs, IDEs, file watchers) pointed at the main repo.
