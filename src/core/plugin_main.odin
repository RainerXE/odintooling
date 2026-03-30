package core

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:os"
import "core:path/filepath"

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

// Plugin initialization
odin_lint_initialize :: proc() -> bool {
    log.infof("Odin-lint plugin initialized")
    return true
}

// Plugin configuration
odin_lint_configure :: proc() -> bool {
    log.infof("Odin-lint plugin configured")
    return true
}

// Plugin shutdown
odin_lint_shutdown :: proc() {
    log.infof("Odin-lint plugin shutdown")
}

// Get plugin info
odin_lint_get_info :: proc() -> InfoHandle {
    return InfoHandle{
        name = "odin-lint",
        version = "0.1.0",
        description = "A linter for the Odin programming language",
        author = "Odin-Lint Team",
    }
}

// Analyze a file and return diagnostics
odin_lint_analyze_file :: proc(document: rawptr, ast: rawptr) -> rawptr {
    log.infof("Odin-lint plugin analyzing file")
    // For now, return a hard-coded test diagnostic
    // In a real implementation, this would analyze the AST and return diagnostics
    return nil
}