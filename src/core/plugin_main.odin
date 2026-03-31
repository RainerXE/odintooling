package core

import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:os"
import "core:path/filepath"
import "base:runtime"

// The OLSPlugin instance — static, allocated once
_odin_lint_plugin_instance: PluginHandle

// The exported entry point OLS calls after dynlib.load_library
@(export)
get_odin_lint_plugin :: proc "c" () -> rawptr {
    // Return a pointer to an OLSPlugin struct with all procs wired
    // Note: we return rawptr because OLSPlugin is defined in OLS,
    // not in this package. OLS casts it to ^OLSPlugin.
    plugin := &_odin_lint_plugin_instance
    plugin.initialize    = odin_lint_initialize
    plugin.analyze_file  = odin_lint_analyze_file
    plugin.configure     = odin_lint_configure
    plugin.shutdown      = odin_lint_shutdown
    plugin.get_info      = odin_lint_get_info
    return plugin
}

// PluginHandle mirrors OLSPlugin from OLS — must match field layout exactly
PluginHandle :: struct {
    initialize:   proc "c" (rawptr) -> bool,
    analyze_file: proc "c" (^byte, rawptr) -> rawptr,
    configure:    proc "c" () -> bool,
    shutdown:     proc "c" (),
    get_info:     proc "c" () -> InfoHandle,
}

InfoHandle :: struct {
    name:        cstring,
    version:     cstring,
    description: cstring,
    author:      cstring,
}

// Plugin initialization
odin_lint_initialize :: proc "c" (config: rawptr) -> bool {
    // Cannot log in C-compatible functions (no context)
    return true
}

// Plugin configuration
odin_lint_configure :: proc "c" () -> bool {
    // Cannot log in C-compatible functions (no context)
    return true
}

// Plugin shutdown
odin_lint_shutdown :: proc "c" () {
    // Cannot log in C-compatible functions (no context)
}

// Get plugin info
odin_lint_get_info :: proc "c" () -> InfoHandle {
    // TODO: Return proper cstrings (^byte)
    return InfoHandle{
        name = nil,
        version = nil,
        description = nil,
        author = nil,
    }
}

// Analyze a file and return diagnostics
odin_lint_analyze_file :: proc "c" (file_path: ^byte, ast: rawptr) -> rawptr {
    // Cannot log in C-compatible functions (no context)
    // For now, return a hard-coded test diagnostic
    // In a real implementation, this would analyze the AST and return diagnostics
    return nil
}
