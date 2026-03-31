# Build Scripts Documentation

## Current Scripts

### Working Scripts
1. `scripts/build.sh` - Main odin-lint build script ✅
2. `build/build.odin` - Odin-based build entry point ✅
3. `build/build_plugin.odin` - Plugin build module ✅

### OLS Scripts (vendor/ols/ exists but integration is unfinished)
1. `scripts/build_ols_standalone.sh` - Builds OLS standalone ❌ (integration unfinished)
2. `scripts/build_ols_with_odinlint.sh` - Builds OLS with odin-lint plugin ❌ (integration unfinished)
3. `scripts/build_all.sh` - Builds both odin-lint and OLS ❌ (unfinished, needs update)
4. `scripts/dev_setup.sh` - OLS development setup ❌ (integration unfinished)

## Architecture

### odin-lint (Current Project)
- `scripts/build.sh` → Main build script
- `build/build.odin` → Odin build entry
- `build/build_plugin.odin` → Plugin module
- `scripts/build_plugin.sh` → Plugin build script

### OLS (Future/Optional)
- Requires `vendor/ols/` directory
- All OLS scripts are currently non-functional
- Can be removed if not needed

## Recommendation

Keep:
- `scripts/build.sh` (main odin-lint build)
- `build/build.odin` (Odin build system)
- `build/build_plugin.odin` (plugin support)
- `scripts/build_plugin.sh` (plugin build script)

Remove:
- OLS scripts (if not needed)
- Or document as "future work"

## Status

### Working Scripts
- `scripts/build.sh` ✅
- `build/build.odin` ✅
- `build/build_plugin.odin` ✅
- `scripts/build_plugin.sh` ✅

### Unfinished Scripts (Need Update)
- `scripts/build_all.sh` ❌ (unfinished, needs update)
- `scripts/build_ols_standalone.sh` ❌ (integration unfinished)
- `scripts/build_ols_with_odinlint.sh` ❌ (integration unfinished)
- `scripts/dev_setup.sh` ❌ (integration unfinished)

## Decision Needed

Should we:
1. Keep OLS scripts for future use?
2. Remove OLS scripts (cleaner, focused)
3. Document as "future work"?

Current state: `vendor/ols/` exists but the integration is unfinished/corrupt, so OLS scripts are non-functional.
