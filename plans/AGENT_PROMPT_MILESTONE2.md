# Agent Prompt: odin-lint OLS Plugin — Complete the Real Library Loading

## Your Task

You are continuing work on the `odintooling` project. The OLS plugin
system is already substantially wired. Your job is to complete **one
specific remaining gap** and then verify the end-to-end plugin flow works.

---

## Project Location

```
/Users/rainer/SynologyDrive/Development/MyODIN/odintooling/
```

Read the updated plans before doing anything:
- `plans/odin-lint-ols-integration-plan.md`  — what is done and what is not
- `plans/odin-lint-implementation-planV4.md` — full milestone structure

---

## What Is Already Done (do not redo this)

The following is already implemented and working. Verify by reading the
files before making changes.

| What | Where |
|------|-------|
| `plugin_manager: PluginManager` global declared | `vendor/ols/src/server/check.odin` line 57 |
| `plugin_manager` created + `initialize_plugins` called | `check.odin` lines 82-87 (inside `create_and_start_check_worker`) |
| `analyze_with_plugins` called on every document parse | `vendor/ols/src/server/documents.odin` lines 334-344 |
| `OLSPlugin` interface struct | `vendor/ols/src/server/plugin.odin` |
| `platform_load_plugin` / `platform_get_function` (real dynlib) | `vendor/ols/src/server/plugin_dynamic.odin` |
| odin-lint builds as `.dylib` | `artifacts/odin-lint-plugin.dylib` exists |

---

## The One Remaining Gap

`load_plugin_library` in `plugin_manager.odin` still SIMULATES loading:

```odin
// Current (broken) — file: vendor/ols/src/server/plugin_manager.odin
load_plugin_library :: proc(path: string) -> LoadedPluginLibrary {
    // ...
    log.infof("Simulating plugin load from: %s", path)   // ← simulation
    lib.loaded = true
    lib.plugin_info = PluginInfo{ name = "Simulated Plugin", ... }
    return lib
}
```

It never calls `platform_load_plugin` from `plugin_dynamic.odin` and
never resolves any symbols via `dynlib.symbol_address`.

Also, `create_plugin_wrapper` returns a wrapper with stub procs that do
nothing — it is never connected to the real loaded library's functions.

---

## What You Need To Implement

### Step 1: Define the plugin entry point type

Add to `plugin_manager.odin` (top, after imports):

```odin
// The single symbol that every odin-lint .dylib must export
PluginEntryProc :: proc "c" () -> ^OLSPlugin
```

### Step 2: Replace `load_plugin_library` with real loading

Replace the existing `load_plugin_library` proc entirely:

```odin
load_plugin_library :: proc(path: string, allocator: mem.Allocator) -> (^OLSPlugin, bool) {
    dp := platform_load_plugin(path)
    if !dp.loaded {
        log.errorf("[PluginManager] Failed to load library: %s", path)
        return nil, false
    }

    raw := platform_get_function(dp, "get_odin_lint_plugin")
    if raw == nil {
        log.errorf("[PluginManager] Symbol 'get_odin_lint_plugin' not found in: %s", path)
        platform_unload_plugin(dp)
        return nil, false
    }

    entry := cast(PluginEntryProc)raw
    plugin := entry()
    if plugin == nil {
        log.errorf("[PluginManager] Entry proc returned nil from: %s", path)
        platform_unload_plugin(dp)
        return nil, false
    }

    log.infof("[PluginManager] Loaded plugin '%s' v%s from %s",
              plugin.get_info().name, plugin.get_info().version, path)
    return plugin, true
}
```

### Step 3: Update `load_plugins_from_config` to use the new signature

The caller must be updated since `load_plugin_library` now returns
`(^OLSPlugin, bool)` instead of `LoadedPluginLibrary`. Replace the
relevant section in `load_plugins_from_config`:

```odin
plugin, ok := load_plugin_library(plugin_config.path, manager.allocator)
if !ok {
    log.errorf("Failed to load plugin: %s", plugin_config.path)
    continue
}

if !register_plugin(manager, plugin) {
    log.errorf("Failed to register plugin: %s", plugin.get_info().name)
    continue
}
```

Remove the now-unused `create_plugin_wrapper`, `get_plugin_info`,
`unload_plugin_library`, `loaded_libraries` field, and the old
`LoadedPluginLibrary` struct from `plugin_manager.odin` — they are
replaced by the simpler direct loading approach above.

### Step 4: Implement `get_odin_lint_plugin` in the odin-lint .dylib

File: `src/core/plugin_main.odin` (create if it does not exist)

This file must be compiled into `odin-lint-plugin.dylib`. It exports
the entry point that OLS calls:

```odin
package core

import "core:odin/ast"
import "core:log"
import "core:strings"

// The OLSPlugin instance — static, allocated once
_odin_lint_plugin_instance: OdinLintPlugin

OdinLintPlugin :: struct {
    initialized: bool,
}

// The exported entry point OLS calls after dynlib.load_library
@(export)
get_odin_lint_plugin :: proc "c" () -> rawptr {
    // Return a pointer to an OLSPlugin struct with all procs wired
    // Note: we return rawptr because OLSPlugin is defined in OLS,
    // not in this package. OLS casts it to ^OLSPlugin.
    plugin := new(PluginHandle)
    plugin.initialize    = odin_lint_initialize
    plugin.analyze_file  = odin_lint_analyze_file
    plugin.configure     = odin_lint_configure
    plugin.shutdown      = odin_lint_shutdown
    plugin.get_info      = odin_lint_get_info
    return plugin
}

// PluginHandle mirrors OLSPlugin from OLS — must match field layout exactly
PluginHandle :: struct {
    initialize:   proc() -> bool,
    analyze_file: proc(document: rawptr, ast: rawptr) -> rawptr,
    configure:    proc() -> bool,
    shutdown:     proc(),
    get_info:     proc() -> InfoHandle,
}

InfoHandle :: struct {
    name:        cstring,
    version:     cstring,
    description: cstring,
    author:      cstring,
}
```

**IMPORTANT NOTE for the agent:** The struct layout above is a starting
point. The actual ABI must match `OLSPlugin` in `vendor/ols/src/server/plugin.odin`
exactly. Read that file first and mirror the field order and calling
conventions precisely. The `analyze_file` proc signature in OLS is:
`proc(document: rawptr, ast: ^ast.File) -> [dynamic]Diagnostic`
— but since `Diagnostic` is an OLS type, you will need to use `rawptr`
and a C-compatible return if crossing the dylib boundary, OR restructure
so the plugin returns a simple array of structs that OLS can decode.

**Recommended simpler approach for Step 4:**
Rather than trying to pass complex Odin types across the dylib boundary,
implement `analyze_file` to return a null-terminated array of a simple
C-compatible diagnostic struct. See `plans/odin-lint-ols-integration-plan.md`
for the design decision on this.

---

## Verification Steps

After implementing, verify each step before the next:

**Verify Step 2:**
```bash
cd /Users/rainer/SynologyDrive/Development/MyODIN/odintooling
# Build OLS with your changes
cd vendor/ols && ./build.sh
# Check it compiles without errors
```

**Verify Step 3:**
```bash
# Check the .dylib exports the symbol correctly
nm -gU artifacts/odin-lint-plugin.dylib | grep get_odin_lint_plugin
# Should show: T _get_odin_lint_plugin  (or similar)
```

**Verify Step 4 (end-to-end):**
Create `test_ols.json` in the project root:
```json
{
    "enable": true,
    "plugins": [{
        "name": "odin-lint",
        "path": "/Users/rainer/SynologyDrive/Development/MyODIN/odintooling/artifacts/odin-lint-plugin.dylib",
        "enabled": true
    }]
}
```
Start OLS pointed at this config and open a `.odin` file in VS Code.
Check the OLS log for: `[PluginManager] Loaded plugin 'odin-lint'`

---

## Key Files to Read Before Starting

Read these files in order before writing any code:

1. `vendor/ols/src/server/plugin.odin` — OLSPlugin struct layout
2. `vendor/ols/src/server/plugin_dynamic.odin` — platform_load_plugin / platform_get_function
3. `vendor/ols/src/server/plugin_manager.odin` — what needs to change
4. `vendor/ols/src/server/check.odin` lines 50-90 — how plugin_manager is declared and init'd
5. `vendor/ols/src/server/documents.odin` lines 315-360 — where analyze_with_plugins is called
6. `src/core/odin_lint_plugin_simple.odin` — existing plugin skeleton to build on

---

## What NOT To Do

- Do NOT create a standalone LSP server — that is the wrong architecture
  (the file `src/core/lsp_server.odin` should be moved to `archive/`)
- Do NOT use tree-sitter in the OLS plugin — OLS passes `^ast.File` directly
- Do NOT change `documents.odin` or `check.odin` — the wiring is already there
- Do NOT rewrite `plugin_dynamic.odin` — `platform_load_plugin` already works
- Do NOT add a new `DiagnosticType` enum value yet — use `.Syntax` as documents.odin already does

---

## Success Criteria

You are done when:
1. `vendor/ols` builds without errors after your changes
2. `nm -gU artifacts/odin-lint-plugin.dylib | grep get_odin_lint_plugin` finds the symbol
3. OLS log shows `[PluginManager] Loaded plugin 'odin-lint'` when configured
4. The plugin's `analyze_file` is called (add a `log.infof` to confirm)
5. At minimum a hard-coded test diagnostic with `source: "odin-lint"` appears
   in the VS Code Problems panel when any `.odin` file is opened

Real rule analysis (C001 firing on actual violations) is Milestone 3 —
do not attempt it in this session. The goal here is proving the pipe works.
