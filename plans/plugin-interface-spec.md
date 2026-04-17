# OLS Plugin Interface Specification

**Document purpose:** Defines the plugin system added to the Odin Language Server (OLS)
to support odin-lint and future extensions. Intended as the basis for an upstream
pull request to [DanielGavin/ols](https://github.com/DanielGavin/ols).

**Status:** Draft — in active development
**OLS fork:** https://github.com/RainerXE/ols
**Last updated:** April 2026

---

## 1. Problem Statement

OLS (Odin Language Server) has no extensibility mechanism. Every feature must be
built directly into the OLS codebase. This creates two problems:

1. **odin-lint cannot deliver real-time editor diagnostics** without forking OLS
   and maintaining a permanent divergence.
2. **Other tools** (refactoring engines, custom completion providers, documentation
   generators) face the same dead end.

This spec defines a minimal, upstream-ready plugin interface that solves both problems
without adding complexity to the OLS core.

---

## 2. Design Goals

| Goal | Rationale |
|------|-----------|
| Multiple plugins | odin-lint is the first; a refactoring plugin or doc generator may follow |
| Multiple capability types | Diagnostics for M5; code actions, hover, rename for later milestones |
| C-ABI compatible | Plugins are `.dylib` / `.so` / `.dll` — loaded with `dynlib` at runtime |
| Capability flags upfront | OLS skips hooks for plugins that don't implement them — zero overhead |
| Clear memory ownership | Plugin allocates results; OLS calls `free_result` when done — no cross-boundary allocator assumptions |
| Upstream-ready | Minimal surface, no odin-lint-specific assumptions, documented for reviewers unfamiliar with odin-lint |

### Reference: pylsp (Python LSP Server)

The design is principled on [pylsp's hook system](https://github.com/python-lsp/python-lsp-server/blob/develop/pylsp/hookspecs.py),
which is the most complete and well-proven plugin architecture in the LSP ecosystem:

- **Named hook per LSP capability** — one function pointer per feature
- **Two composition modes**:
  - *Merge-all*: every plugin is called, results are concatenated (diagnostics, code actions, completions)
  - *First-result*: first plugin returning non-nil wins (hover, format, rename)
- **Pluggy** manages the Python registry; we use a simple `[dynamic]^OLSPlugin` in Odin

---

## 3. Interface Definition

The full interface lives in `src/server/plugin.odin` inside the OLS repo.

### 3.1 Capability Flags

```odin
// PluginCapability declares which hooks a plugin implements.
// OLS uses this at call time to skip plugins that don't handle a feature.
PluginCapability :: enum u32 {
    Diagnostics  = 0,  // on_diagnostics — merge-all
    CodeActions  = 1,  // on_code_actions — merge-all
    Hover        = 2,  // on_hover — first-result
    Completions  = 3,  // on_completions — merge-all (future)
    Format       = 4,  // on_format — first-result (future)
    Rename       = 5,  // on_rename — first-result (future)
}

PluginCapabilities :: bit_set[PluginCapability; u32]
```

### 3.2 Shared Data Types

```odin
// OLSPosition mirrors the LSP Position type (0-indexed).
OLSPosition :: struct #packed {
    line:      i32,
    character: i32,
}

// OLSRange mirrors the LSP Range type.
OLSRange :: struct #packed {
    start: OLSPosition,
    end:   OLSPosition,
}

// OLSSeverity mirrors LSP DiagnosticSeverity.
OLSSeverity :: enum i32 {
    Error       = 1,
    Warning     = 2,
    Information = 3,
    Hint        = 4,
}

// OLSDocument is passed to every hook. It exposes the file content and
// the parsed AST. Plugins that need the AST cast `ast` to `^ast.File`
// — this is safe only for plugins compiled against the same Odin version
// as OLS. Plugins that only need text analysis use `text`/`text_len`.
OLSDocument :: struct #packed {
    uri:      cstring,  // "file:///absolute/path.odin"
    path:     cstring,  // "/absolute/path.odin"
    text:     [^]u8,    // raw UTF-8 file content
    text_len: i32,
    ast:      rawptr,   // ^ast.File — nil if not yet parsed
}
```

### 3.3 Result Types

```odin
// A single diagnostic produced by a plugin.
OLSDiagnostic :: struct #packed {
    range:    OLSRange,
    severity: OLSSeverity,
    code:     cstring,    // rule ID, e.g. "C001"
    source:   cstring,    // plugin name, e.g. "odin-lint"
    message:  cstring,
    has_fix:  bool,
    fix_hint: cstring,    // human-readable; nil if has_fix == false
}

// A list of diagnostics returned by on_diagnostics.
// The plugin owns this memory; OLS calls free_result(items) when done.
OLSDiagnosticList :: struct #packed {
    items: [^]OLSDiagnostic,
    count: i32,
}

// A text edit applied by a code action.
OLSTextEdit :: struct #packed {
    range:    OLSRange,
    new_text: cstring,
}

// A single code action produced by a plugin.
OLSCodeAction :: struct #packed {
    title:       cstring,  // shown in the editor menu
    kind:        cstring,  // "quickfix" | "refactor" | "refactor.extract" | etc.
    is_preferred: bool,
    edit:        OLSTextEdit,
}

// A list of code actions returned by on_code_actions.
OLSCodeActionList :: struct #packed {
    items: [^]OLSCodeAction,
    count: i32,
}
```

### 3.4 The Plugin Struct

```odin
// OLSPlugin is the complete plugin interface.
// A plugin fills this struct and returns a pointer from its entry point.
// OLS reads capabilities at load time and calls only the relevant hooks.
OLSPlugin :: struct {
    // ── Identity ────────────────────────────────────────────────────────
    name:         cstring,
    version:      cstring,
    capabilities: PluginCapabilities,

    // ── Lifecycle ────────────────────────────────────────────────────────
    // init is called once after the plugin is loaded.
    // host_api_version is the OLS plugin API version string (e.g. "1.0").
    // Return false to refuse loading (version mismatch, missing config, etc.).
    init:     proc "c" (host_api_version: cstring) -> bool,

    // shutdown is called once before OLS exits or the plugin is unloaded.
    shutdown: proc "c" (),

    // ── Merge-all hooks ──────────────────────────────────────────────────
    // All registered plugins implementing these are called.
    // Results are concatenated into OLS's diagnostic/action lists.

    // on_diagnostics is called after every file save and on open.
    // Return nil if no diagnostics for this file.
    on_diagnostics:  proc "c" (doc: ^OLSDocument) -> ^OLSDiagnosticList,

    // on_code_actions is called when the editor requests fixes for a range.
    // Return nil if no actions available.
    on_code_actions: proc "c" (doc: ^OLSDocument, range: OLSRange) -> ^OLSCodeActionList,

    // ── First-result hooks ───────────────────────────────────────────────
    // The first plugin returning non-nil wins; remaining plugins are skipped.

    // on_hover returns markdown text for the symbol at pos.
    // Return nil to pass to the next plugin (or OLS built-in hover).
    on_hover: proc "c" (doc: ^OLSDocument, pos: OLSPosition) -> cstring,

    // on_rename returns workspace edits for renaming the symbol at pos.
    on_rename: proc "c" (doc: ^OLSDocument, pos: OLSPosition, new_name: cstring) -> ^OLSCodeActionList,

    // ── Memory ───────────────────────────────────────────────────────────
    // OLS calls free_result(list.items) when it is done with a result.
    // The plugin must handle freeing the array and all cstrings within it.
    free_result: proc "c" (ptr: rawptr),
}
```

### 3.5 Plugin Entry Point

Every plugin `.dylib` must export exactly one symbol:

```odin
@(export)
ols_plugin_get :: proc "c" () -> ^OLSPlugin
```

OLS calls this immediately after `dynlib.load_library`. If it returns nil,
the plugin is unloaded and an error is logged.

---

## 4. OLS Changes Required

All changes to OLS are isolated to new files or clearly marked sections.
Existing OLS behaviour is unchanged when no plugins are loaded.

### 4.1 New file: `src/server/plugin.odin`

Contains all types from Section 3 plus:

```odin
// Plugin registry — populated at startup, read-only during operation.
plugin_registry: [dynamic]^OLSPlugin

// Load all plugins listed in config.plugins.
plugin_registry_init :: proc(config: ^common.Config) { ... }

// Call on_diagnostics on all registered plugins; add results to OLS store.
plugin_run_diagnostics :: proc(doc: ^Document, uri: string) { ... }

// Call on_code_actions on all registered plugins; append to existing list.
plugin_run_code_actions :: proc(doc: ^Document, range: common.Range, actions: ^[dynamic]CodeAction) { ... }

// Unload all plugins.
plugin_registry_shutdown :: proc() { ... }
```

### 4.2 Modified: `src/server/diagnostics.odin`

Add `Plugin` to `DiagnosticType` enum:

```odin
DiagnosticType :: enum {
    Syntax,
    Unused,
    Check,
    Plugin,   // ← new: diagnostics from loaded plugins
}
```

### 4.3 Modified: `src/server/check.odin`

After the check worker completes and publishes its diagnostics, call:
```odin
plugin_run_diagnostics(doc, uri)
```

### 4.4 Modified: `src/server/action.odin`

At the end of `get_code_actions`, before returning:
```odin
plugin_run_code_actions(document, range, &actions)
```

### 4.5 Modified: `src/common/config.odin`

Add plugin list to config schema:
```odin
PluginConfig :: struct {
    name:    string,
    path:    string,
    enabled: bool,
}
// Added to Config struct:
plugins: []PluginConfig
```

---

## 5. ols.json Schema Addition

```json
{
  "plugins": [
    {
      "name": "odin-lint",
      "path": "/path/to/artifacts/odin-lint-plugin.dylib",
      "enabled": true
    }
  ]
}
```

---

## 6. odin-lint Plugin Implementation

odin-lint implements `ols_plugin_get` in `src/core/plugin_main.odin`.

The `on_diagnostics` hook:
1. Calls the existing `analyze_file` pipeline
2. Converts `[]Diagnostic` → `OLSDiagnosticList` (C-compatible copy)
3. Returns the list; OLS calls `free_result` when done

The `on_code_actions` hook:
1. Calls `generate_fixes` for the file
2. Filters to fixes whose range overlaps the requested range
3. Returns `OLSCodeActionList`

---

## 7. API Versioning

The `host_api_version` string passed to `init` follows semver: `"1.0"`.

Breaking changes (struct layout, removed hooks) increment the major version.
New hooks (additive) increment the minor version. Plugins check the version
in `init` and return `false` if incompatible.

Current version: **`1.0`**

---

## 8. Changelog

All changes to OLS code are documented here for the upstream PR reviewer.

| Date | File | Change | Reason |
|------|------|--------|--------|
| 2026-04-17 | `src/server/plugin.odin` | **New file**: all types (§3), registry, `plugin_registry_init`, `plugin_run_diagnostics`, `plugin_run_code_actions`, `plugin_registry_shutdown` | Core of the plugin system |
| 2026-04-17 | `src/server/diagnostics.odin` | Add `Plugin` to `DiagnosticType` enum | Separate plugin diagnostics from Syntax/Unused/Check |
| 2026-04-17 | `src/common/config.odin` | Add `PluginConfig` struct; add `plugins: []PluginConfig` to `Config` | Runtime plugin list populated from ols.json |
| 2026-04-17 | `src/server/types.odin` | Add `OlsPluginConfig` struct; add `plugins: [dynamic]OlsPluginConfig` to `OlsConfig` | JSON schema for ols.json plugin entries |
| 2026-04-17 | `src/server/requests.odin` | `read_ols_initialize_options`: copy `ols_config.plugins` → `config.plugins`; `request_initialize`: call `plugin_registry_init` after config is loaded; `notification_did_open` / `notification_did_save`: call `plugin_run_diagnostics` before `push_diagnostics` | Wire up config loading and per-file diagnostic triggering |
| 2026-04-17 | `src/server/action.odin` | Call `plugin_run_code_actions` at end of `get_code_actions` before return | Merge plugin quick-fixes into the editor's action menu |
| 2026-04-17 | `src/main.odin` | Add `defer server.plugin_registry_shutdown()` after check worker start | Ensure plugins are unloaded cleanly on exit |

### Implementation notes

- `plugin_registry_init` is called at the end of `request_initialize` (not at process start) because `config.plugins` is only populated after `read_ols_initialize_options` runs.
- `plugin_run_diagnostics` is **nil-safe** and a no-op when no plugins are loaded, so there is zero overhead in the common case.
- Plugin diagnostics are cleared and re-added on every open/save so stale results never linger.
- The `check.odin` worker is deliberately **not** wired to plugins: `odin check` is directory-scoped while `on_diagnostics` is file-scoped. Plugins get fresh results on the next save.

---

## 9. Out of Scope (Future Milestones)

| Capability | Milestone | Notes |
|------------|-----------|-------|
| `on_completions` | M5+ | Merge-all; plugins augment completions |
| `on_hover` | M5+ | First-result; plugin hover overrides OLS built-in |
| `on_rename` | M6 | First-result; complex workspace edit |
| `on_format` | M6 | First-result; alternative formatter |
| Cross-file / workspace hooks | M5.6 | DNA/call-graph export integration |
