package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:os"
import "core:path/filepath"
import "base:runtime"

// Import the OLS types that we need to use
// These types must match exactly what OLS expects
PluginInfo :: struct {
    name:        string,
    version:     string,
    description: string,
    author:      string,
}

// Simple diagnostic structure that matches OLS Diagnostic
// We'll use a simplified version that can be passed across the dylib boundary
SimpleDiagnostic :: struct {
    line:    i32,
    column:  i32,
    severity: i32,  // 1=Error, 2=Warning, 3=Information, 4=Hint
    code:    string,
    source:  string,
    message: string,
}

// The OLSPlugin interface that matches what OLS expects
OLSPlugin :: struct {
    initialize:   proc() -> bool,
    analyze_file: proc(document: rawptr, ast: ^ast.File) -> [dynamic]SimpleDiagnostic,
    configure:    proc() -> bool,
    shutdown:     proc(),
    get_info:     proc() -> PluginInfo,
}

// The exported entry point OLS calls after dynlib.load_library
@(export)
get_odin_lint_plugin :: proc "c" () -> rawptr {
    // Return a pointer to an OLSPlugin struct with all procs wired
    // Note: we return rawptr because OLSPlugin is defined in OLS,
    // not in this package. OLS casts it to ^OLSPlugin.
    context = runtime.default_context()
    plugin := new(OLSPlugin, context.allocator)
    plugin.initialize    = odin_lint_initialize
    plugin.analyze_file  = odin_lint_analyze_file
    plugin.configure     = odin_lint_configure
    plugin.shutdown      = odin_lint_shutdown
    plugin.get_info      = odin_lint_get_info
    return plugin
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
odin_lint_get_info :: proc() -> PluginInfo {
    return PluginInfo{
        name = "odin-lint",
        version = "0.1.0",
        description = "A linter for the Odin programming language",
        author = "Odin-Lint Team",
    }
}

// Analyze a file and return diagnostics
odin_lint_analyze_file :: proc(document: rawptr, ast: ^ast.File) -> [dynamic]SimpleDiagnostic {
    log.infof("Odin-lint plugin analyzing file - this should appear in OLS logs")
    
    // For now, return a hard-coded test diagnostic
    // In a real implementation, this would analyze the AST and return diagnostics
    diagnostics := make([dynamic]SimpleDiagnostic, 0, context.allocator)
    
    // Add a test diagnostic
    test_diag := SimpleDiagnostic{
        line = 1,
        column = 1,
        severity = 2,  // Warning
        code = "TEST001",
        source = "odin-lint",
        message = "This is a test diagnostic from odin-lint plugin - if you see this, the plugin is working!",
    }
    append(&diagnostics, test_diag)
    
    log.infof("Odin-lint plugin returning %d diagnostics", len(diagnostics))
    return diagnostics
}