# odin-lint — OLS Integration Plan
*Version 4 · Updated after full codebase review · March 2026*

---

## Honest Current State

This document supersedes all earlier versions. Status claims have been
reconciled against actual source code in `vendor/ols/src/server/` and `src/core/`.

### What Is Actually Complete ✅

| Item | Evidence in code |
|------|-----------------|
| `OLSPlugin` struct-of-proc-ptrs interface | `server/plugin.odin` |
| `PluginManager` lifecycle procs | `server/plugin_manager.odin` |
| Dynamic library loading via `core:dynlib` | `server/plugin_dynamic.odin` |
| Plugin config field in `common.Config` | `common/config.odin` line 58 |
| Plugin config struct in OLS types | `server/types.odin` line 452 |
| `PluginDiagnostic` and `QuickFix` types | `server/plugin.odin` |
| Symbol name resolution approach understood | Integration plan notes |
| Simple test plugin builds and loads as `.dylib` | `simple_test_plugin.dylib` exists |
| odin-lint builds as shared library | `odin-lint-plugin.dylib` exists |

### What Is NOT Done Yet ❌

These are the concrete gaps found in the code review. They are the only
things blocking a working end-to-end integration.

**Gap 1 — Plugin manager never initialised in OLS startup**
`vendor/ols/src/main.odin` has comment `// Initialize plugin system`
but no actual call to `initialize_plugins`. `PluginManager` is never
instantiated in the running process.

**Gap 2 — `analyze_with_plugins` is never called from the OLS pipeline**
The proc exists in `plugin_manager.odin` but is called from nowhere.
The OLS document analysis flow (`documents.odin` → `check.odin` →
`diagnostics.odin`) has no hook into the plugin system. Plugin
diagnostics never reach the editor.

**Gap 3 — `load_plugin_library` still simulates loading**
The proc logs "Simulating plugin load" and returns a fake struct
without calling `platform_load_plugin` from `plugin_dynamic.odin`.
The two files are not connected.

**Gap 4 — Symbol resolution not implemented after `dynlib.load_library`**
After loading the `.dylib` there is no call to `dynlib.symbol_address`
to resolve the entry point and wire proc pointers into an `OLSPlugin`.
A successfully-loaded library still cannot be called.

**Gap 5 — `PluginDiagnostic` vs `Diagnostic` type mismatch**
`analyze_file` returns `[dynamic]Diagnostic` (OLS native type) but
`plugin.odin` defines `PluginDiagnostic` as a separate extended struct.
No conversion layer exists. Rule metadata (`rule_id`, `fix_suggestion`)
will be lost.

**Gap 6 — Tree-sitter FFI is a placeholder**
`src/core/tree_sitter.odin` returns `false` from every function and
produces empty `ASTNode{}`. C001 and C002 operate on a placeholder AST
with `node_type = "placeholder"` and no children — they detect nothing.

---

## Architecture (Confirmed)

```
Editor (VS Code / Neovim / Helix)
    │ LSP JSON-RPC
    ▼
OLS binary  ──── ols.json ──── plugins: [{path, enabled}]
    │
    ├── [GAP 1] initialize_plugins() — not called at startup
    │
    ├── on didOpen / didChange:
    │     document analysis pipeline
    │     [GAP 2] analyze_with_plugins() — not called here
    │                  │
    │                  ▼ (when wired)
    │           odin-lint-plugin.dylib
    │                  │
    │                  ▼
    │           C001, C002 rules
    │           [GAP 6] need real AST — use ^ast.File from OLS
    │
    └── diagnostics.odin → publishDiagnostics → Editor
         [GAP 2] Plugin DiagnosticType bucket missing
```


---

## Fix Plan — Work Through In Order

### Fix 1 — Connect `load_plugin_library` to `platform_load_plugin`

**File:** `vendor/ols/src/server/plugin_manager.odin`

```odin
PluginEntryPoint :: proc "c" () -> ^OLSPlugin

load_plugin_library :: proc(path: string, allocator: mem.Allocator) -> (^OLSPlugin, bool) {
    dp := platform_load_plugin(path)
    if !dp.loaded {
        log.errorf("[PluginManager] Failed to load: %s", path)
        return nil, false
    }
    entry_raw := platform_get_function(dp, "get_odin_lint_plugin")
    if entry_raw == nil {
        log.errorf("[PluginManager] Symbol not found in: %s", path)
        platform_unload_plugin(dp)
        return nil, false
    }
    entry := cast(PluginEntryPoint)entry_raw
    plugin := entry()
    if plugin == nil {
        platform_unload_plugin(dp)
        return nil, false
    }
    log.infof("[PluginManager] Loaded '%s' from %s", plugin.get_info().name, path)
    return plugin, true
}
```

The odin-lint `.dylib` must export this entry point:

```odin
// src/core/plugin_main.odin  (compiled into odin-lint-plugin.dylib)
@(export)
get_odin_lint_plugin :: proc "c" () -> ^server.OLSPlugin {
    // return pointer to static OLSPlugin with all procs wired
}
```

**Gate:** `dynlib.symbol_address("get_odin_lint_plugin")` returns non-nil.
`plugin.get_info().name` returns `"odin-lint"`.

---

### Fix 2 — Add `Plugin` DiagnosticType

**File:** `vendor/ols/src/server/diagnostics.odin`

```odin
// Before:
DiagnosticType :: enum { Syntax, Unused, Check }

// After:
DiagnosticType :: enum { Syntax, Unused, Check, Plugin }
```

Plugin diagnostics get their own slot so they can be cleared independently
when a plugin is disabled without touching OLS's own diagnostics.

**Gate:** `add_diagnostics(.Plugin, uri, diag)` compiles; diagnostic
appears in `get_merged_diagnostics()`.

---

### Fix 3 — Initialise `PluginManager` in OLS startup

**File:** `vendor/ols/src/main.odin`

Add `plugin_manager` to server package-level state, then initialise it:

```odin
// In server package — package-level global:
plugin_manager: PluginManager

// In main.odin run(), after context.logger is set:
server.plugin_manager = server.create_plugin_manager(context.allocator)
server.initialize_plugins(&server.plugin_manager, &common.config)
defer server.shutdown_plugins(&server.plugin_manager)
```

**Gate:** OLS starts and log shows
`"[PluginManager] Loaded plugin 'odin-lint'"` when `ols.json` has a
valid plugin entry.

---

### Fix 4 — Call `analyze_with_plugins` in the document pipeline

**File:** `vendor/ols/src/server/documents.odin` (or `check.odin`)

Find where OLS calls `add_diagnostics(.Syntax, ...)` after parsing.
Add alongside it:

```odin
plugin_diags := analyze_with_plugins(&plugin_manager,
                                      cast(rawptr)document,
                                      document.ast)
for diag in plugin_diags {
    add_diagnostics(.Plugin, document.uri, diag)
}
```

**Gate:** Opening a `.odin` file triggers the plugin's `analyze_file`
(confirmed by log). A hard-coded test diagnostic appears in the editor.


---

### Fix 5 — Resolve `PluginDiagnostic` vs `Diagnostic` type mismatch

**Recommended:** Extend the native `Diagnostic` type in `types.odin`
with optional plugin fields (zero value = not set):

```odin
Diagnostic :: struct {
    // existing OLS fields unchanged
    range:    common.Range,
    severity: DiagnosticSeverity,
    code:     string,
    source:   string,
    message:  string,
    // plugin extensions:
    rule_id:           string,
    fix_suggestion:    string,
    documentation_uri: string,
}
```

Drop `PluginDiagnostic` from `plugin.odin` entirely.

**Gate:** A plugin diagnostic with `rule_id = "C001"` shows the code
`C001` in the editor squiggle tooltip.

---

### Fix 6 — Use OLS's `^ast.File` instead of tree-sitter in the plugin

**Key insight:** OLS has already parsed the file into `^ast.File` using
`core:odin/ast`. The plugin's `analyze_file` receives this directly.
You do NOT need tree-sitter for the OLS plugin path at all.

```odin
// C001 using OLS's already-parsed AST — no tree-sitter required
analyze_c001 :: proc(file: ^ast.File) -> [dynamic]Diagnostic {
    diagnostics: [dynamic]Diagnostic
    v := ast.Visitor{visit = c001_visit, data = &diagnostics}
    ast.walk(&v, file)
    return diagnostics
}

c001_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
    call, ok := node.derived.(^ast.Call_Expr)
    if !ok do return visitor
    ident, is_ident := call.expr.derived.(^ast.Ident)
    if !is_ident do return visitor
    if ident.name != "make" && ident.name != "new" do return visitor
    if !has_defer_free_in_scope(node) {
        diags := cast(^[dynamic]Diagnostic)visitor.data
        append(diags, Diagnostic{
            range    = node_to_lsp_range(node.pos, node.end),
            severity = .Error,
            code     = strings.clone("C001"),
            source   = strings.clone("odin-lint"),
            message  = strings.clone(
                "Allocation without matching defer free in same scope"),
            rule_id  = strings.clone("C001"),
        })
    }
    return visitor
}
```

Tree-sitter remains the right tool for the **standalone CLI**
(`odin-lint <file>`) which has no OLS parser. It is not needed for
the OLS plugin path.

**Gate:** C001 fires on `test/fixtures/fail/c001_allocation.odin`.
C001 does NOT fire on `test/fixtures/pass/c001_proper_free.odin`.
Zero false positives on `vendor/ols/src/` itself.

---

## Revised Phase Plan

### Phase 1 — Wiring (1–2 weeks) 🔄 CURRENT

Apply Fixes 1–5. Goal: prove the full path from editor → plugin → editor
works. No real rule analysis yet — a hard-coded test diagnostic is enough.

**Exit criteria:**
- OLS log confirms plugin loaded at startup
- Opening any `.odin` file triggers plugin (confirmed by log)
- A diagnostic with `source: "odin-lint"` appears in the editor Problems panel

### Phase 2 — Real C001 via OLS AST (1 week)

Apply Fix 6. Walk `^ast.File` for real. C001 fires on genuine violations.

**Exit criteria:**
- C001 fires on `test/fixtures/fail/c001_allocation.odin`
- C001 silent on `test/fixtures/pass/c001_proper_free.odin`
- Zero false positives on OLS's own source tree

### Phase 3 — Remaining correctness rules (2–3 weeks)

Implement C002–C008 using the same `^ast.File` walking pattern.

**Exit criteria:**
- 8 correctness rules implemented
- 3 pass + 3 fail fixtures per rule
- Gate 1 from roadmap fully satisfied

### Phase 4 — Tree-sitter for standalone CLI (parallel)

The `odin-lint <file>` CLI needs tree-sitter because it has no OLS parser.
This can proceed in parallel with Phase 3.

---

## Key Architectural Decisions (Locked)

| Decision | Rationale |
|----------|-----------|
| OLS plugin uses `^ast.File`, not tree-sitter | OLS already parsed it; avoids duplicate parsing and FFI complexity |
| Standalone CLI still uses tree-sitter | CLI has no OLS parser available |
| Plugin entry point: `get_odin_lint_plugin() -> ^OLSPlugin` | Single stable symbol; all procs in one struct |
| Drop `PluginDiagnostic`, extend native `Diagnostic` | Simpler; flows through existing OLS diagnostic infrastructure |
| Add `DiagnosticType.Plugin` | Independent lifecycle from OLS's own diagnostics |

---

## ols.json Configuration (target state)

```json
{
    "enable": true,
    "plugins": [
        {
            "name": "odin-lint",
            "path": "/usr/local/lib/odin-lint-plugin.dylib",
            "enabled": true
        }
    ],
    "odin-lint": {
        "rules": {
            "C001": "error",
            "C002": "error",
            "C003": "warning"
        },
        "exclude": ["vendor/**", "test/**"]
    }
}
```

---

## What To Ignore From Previous Versions

- "Plugin System Complete ✅" — the system is designed and partially built
  but is not yet wired into the OLS event loop
- The standalone LSP server in `src/core/lsp_server.odin` — wrong
  architecture; archive this file
- Tree-sitter as a prerequisite for OLS integration — use `^ast.File`
- Q2 2025 FFI production target — based on a misunderstanding; not needed
  for the plugin path
