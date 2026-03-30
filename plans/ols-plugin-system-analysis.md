# OLS Plugin System Analysis

## Overview

This document analyzes the plugin system in our `feat/plugin-system-v2` branch compared to the upstream OLS master.

---

## Key Files Added in Our Branch

### 1. `src/server/plugin.odin` (NEW)
**Purpose**: Defines the plugin interface that all OLS plugins must implement.

**Key Components**:
- `OLSPlugin` struct: Interface for plugins (initialize, analyze_file, configure, shutdown, get_info).
- `PluginInfo`: Metadata about the plugin (name, version, description, author).
- `PluginDiagnostic`: Extended diagnostic with rule_id, fix_suggestion, etc.
- `QuickFix`: Code actions for automatic fixes.
- `PluginError`: Error categorization.

**Issues**:
- Uses Odin-specific types (e.g., `string`, `[dynamic]Diagnostic`) in the interface.
- **Not C-compatible** (cannot be used directly by dynamic plugins).

---

### 2. `src/server/plugin_manager.odin` (NEW)
**Purpose**: Manages plugin lifecycle (registration, initialization, analysis, cleanup).

**Key Components**:
- `PluginManager` struct: Tracks plugins, allocator, loaded libraries.
- `create_plugin_manager()`: Initializes the manager.
- `initialize_plugins()`: Loads plugins from config.
- `analyze_with_plugins()`: Runs plugins on documents.
- `shutdown_plugins()`: Cleans up plugins.

**Issues**:
- `load_plugin_library()` **simulates loading** (does not call `platform_load_plugin`).
- Not wired into OLS startup (`main.odin` does not call `initialize_plugins`).
- Not wired into document pipeline (`documents.odin` does not call `analyze_with_plugins`).

---

### 3. `src/server/plugin_dynamic.odin` (NEW)
**Purpose**: Dynamic library loading for plugins.

**Key Components**:
- `LoadedPluginLibrary`: Tracks loaded `.dylib`/`.so` files.
- `platform_load_plugin()`: Loads a dynamic library.
- `platform_get_function()`: Resolves symbols (e.g., `get_odin_lint_plugin`).
- `platform_unload_plugin()`: Unloads a library.

**Status**: ✅ **Working** (but unused by `plugin_manager.odin`).

---

## Problems Identified

### 1. **Interface Mismatch**
- **Our plugin interface** (`OLSPlugin`) uses Odin types (`string`, `[dynamic]Diagnostic`).
- **Dynamic plugins** (C/FFI) require C-compatible types (`^byte`, `rawptr`).
- **Solution**: Define a **C-compatible interface** for dynamic plugins.

### 2. **Not Wired into OLS**
- `main.odin` does not call `initialize_plugins()`.
- `documents.odin` does not call `analyze_with_plugins()`.
- **Solution**: Add these calls to the OLS pipeline.

### 3. **Simulated Loading**
- `load_plugin_library()` returns a fake struct instead of calling `platform_load_plugin`.
- **Solution**: Connect `load_plugin_library` to `platform_load_plugin`.

### 4. **Diagnostic Type Mismatch**
- OLS uses `Diagnostic` (native type).
- Plugins use `PluginDiagnostic` (extended type).
- **Solution**: Extend `Diagnostic` or convert between types.

---

## Recommended Fixes

### Fix 1: Define C-Compatible Plugin Interface
```odin
// In src/core/odin_lint_plugin.odin
foreign import odin_lint {
    odin_lint_initialize :: proc "c" (config: rawptr) -> bool
    odin_lint_analyze_file :: proc "c" (file_path: ^byte, ast: rawptr) -> rawptr
    // ... other functions
}
```

### Fix 2: Wire Plugin Manager into OLS
```odin
// In vendor/ols/src/main.odin
plugin_manager := create_plugin_manager(context.allocator)
initialize_plugins(&plugin_manager, &config)
defer shutdown_plugins(&plugin_manager)
```

### Fix 3: Connect `load_plugin_library` to `platform_load_plugin`
```odin
// In vendor/ols/src/server/plugin_manager.odin
load_plugin_library :: proc(path: string) -> (^OLSPlugin, bool) {
    dp := platform_load_plugin(path)
    if !dp.loaded { return nil, false }
    
    entry := cast(proc() -> ^OLSPlugin)(platform_get_function(dp, "get_odin_lint_plugin"))
    plugin := entry()
    return plugin, true
}
```

### Fix 4: Call `analyze_with_plugins` in Document Pipeline
```odin
// In vendor/ols/src/server/documents.odin
plugin_diags := analyze_with_plugins(&plugin_manager, document, ast)
for diag in plugin_diags {
    add_diagnostics(.Plugin, document.uri, diag)
}
```

### Fix 5: Extend `Diagnostic` or Convert Types
```odin
// Option A: Extend native Diagnostic
diagnostic.rule_id = plugin_diag.rule_id

// Option B: Convert PluginDiagnostic to Diagnostic
native_diag := Diagnostic{
    range = plugin_diag.range,
    severity = plugin_diag.severity,
    message = plugin_diag.message,
}
```

---

## Architecture Recommendations

### 1. **Two-Tier Plugin System**
- **Tier 1 (Native)**: Plugins written in Odin (use `OLSPlugin` interface).
- **Tier 2 (Dynamic)**: Plugins written in any language (use C interface).

### 2. **Memory Management**
- **OLS allocates** plugin structs and diagnostics.
- **Plugins return** diagnostics (OLS manages lifetime).

### 3. **Error Handling**
- Plugins return `bool` for success/failure.
- OLS logs errors and continues (graceful degradation).

---

## Next Steps

1. **Fix `plugin_manager.odin`**: Connect to `platform_load_plugin`.
2. **Wire into OLS**: Add calls to `main.odin` and `documents.odin`.
3. **Define C interface**: Update `odin_lint_plugin.odin`.
4. **Test**: Load a simple plugin and verify diagnostics appear.

---

## Conclusion

The plugin system is **designed but not wired**. The core issue is the **interface mismatch** between Odin types and C-compatible types. By:
1. Using a **C-compatible interface** for dynamic plugins.
2. Wiring the plugin manager into OLS.
3. Connecting `load_plugin_library` to `platform_load_plugin`.

We can achieve a working plugin system.
