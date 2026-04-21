# RuiShin C001 Candidate Review

Generated: 2026-04-21 after M6.6 (72 → 39 remaining hits in src/).

## Summary

| Category | Count |
|----------|-------|
| Genuine leak candidates | ~16 |
| Custom allocator vars (M7 Tier 4) | ~14 |
| Non-init-named init procs (M7 Tier 3) | ~5 |
| Manual delete through switch/branch (detection gap) | ~4 |
| **Total remaining** | **39** |

---

## HIGH — Likely genuine leaks

### renderer/error_handling.odin:44
- **Function**: `reset_error_flag` (or similar per-frame reset)
- **Issue**: Map re-allocated every call, no corresponding delete of old map
- **Priority**: HIGH — called per frame

### ui/theme/accessibility.odin:120, 141, 145, 223, 248, 329, 348, 351
- **Function**: Various theme update/recalculate procs
- **Issue**: New maps created for color/style data; old maps appear to be orphaned
- **Priority**: MEDIUM — called on theme changes

---

## MEDIUM — Loop re-allocation pattern

### graphics/text/layout.odin:198, 324, 330
- **Issue**: Maps or slices made inside a loop or per-layout-pass without delete of previous
- **Priority**: MEDIUM

### graphics/svg_parser.odin:309, 373, 503, 1375
- **Issue**: Local maps in parsing functions; no visible delete path
- **Priority**: LOW-MEDIUM (parsing is typically one-shot, but still leaks)

---

## LOW — Verify manually

### graphics/rsd_render.odin:220, 221, 260, 261
- **Issue**: C001 fires but `delete(colors); delete(stops)` exists through a switch structure
  that the checker cannot see. Likely **false positive** — confirm with manual review.
- **Priority**: LOW (likely FP, detection gap)

### graphics/g2d_core.odin:4360, 5968, 5979, 6015, 6163
- **Issue**: Unknown — large file, needs manual inspection
- **Priority**: MEDIUM

### graphics/g2d_draw.odin:870, 1050, 1306, 1310, 1324, 1325, 1408
- **Issue**: Draw procs — need to check if results are returned or freed
- **Priority**: MEDIUM

---

## FALSE POSITIVES (M7 will fix)

### Custom allocator variable names — M7 Tier 4

These fire because the allocator is passed via a variable name that does not contain
the word "allocator" (e.g. `path_scratch`, `frame_scratch`, `arena_alloc`).
M7 will add a `memory_role='allocator'` column to the code graph, allowing the
linter to look up whether a local variable has allocator type.

Files affected: `graphics/g2d_core.odin`, `graphics/g2d_draw.odin`,
`graphics/g2d_text.odin`, `graphics/gpu_asset_manager.odin`, `graphics/font_manager.odin`

### Non-init-named init procs — M7 Tier 3

These are initializer procs that allocate module-lifetime state but are not named
`*_init` / `init_*` / `init`. Examples: `setup`, `load`, `create_*`, `build_*`.
M7 Tier 3 will query the graph for LHS package-level variable writes (init-and-hold).

Files affected: `assets/colors.odin`, `assets/manager.odin`, `graphics/svg_render.odin`

---

## Status

- **Before M6.6**: 72 hits
- **After M6.6**: 39 hits (33 FPs eliminated)
- **After M7 (projected)**: ≤ 5 hits (remaining 19 custom-allocator + init FPs fixed;
  ~16–20 genuine candidates remain as actionable findings)
