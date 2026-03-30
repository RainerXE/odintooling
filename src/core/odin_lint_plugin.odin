package core

import "core:fmt"
import "core:odin/ast"

// OLSPlugin represents the interface that odin-lint exposes to OLS
OLSPlugin :: struct {
    // Plugin metadata
    name:        ^byte,  // cstring
    version:     ^byte,  // cstring
    description: ^byte,  // cstring
    author:      ^byte,  // cstring
    
    // Plugin capabilities
    supports_linting: bool,
    supports_formatting: bool,
    supports_analysis: bool,
}

// Diagnostic represents a linting diagnostic (matches OLS Diagnostic structure)
PluginDiagnostic :: struct {
    file:    ^byte,  // cstring
    line:    i32,
    column:  i32,
    rule_id: ^byte,  // cstring
    tier:    ^byte,  // cstring
    message: ^byte,  // cstring
    fix:     ^byte,  // cstring
    has_fix: bool,
}

// Static string definitions for plugin metadata
// Using string literals with explicit null terminators
plugin_name_str: []byte = "odin-lint"
plugin_version_str: []byte = "0.1.0"
plugin_desc_str: []byte = "Static analysis linter for Odin"
plugin_author_str: []byte = "RuiShin Projects"

// Convert to null-terminated arrays at compile time
plugin_name: [10]byte
plugin_version: [6]byte  
plugin_desc: [30]byte
plugin_author: [16]byte

// Initialization block would go here if Odin supported it
// For now, we'll use a different approach
=======
// For "c" calling convention, we need to use a simpler approach
// Let's use constants and build the strings differently

// Export the plugin instance for OLS to load
// This function will be called by OLS to get the plugin interface
@(export)
get_odin_lint_plugin :: proc "c"() -> OLSPlugin {
    return OLSPlugin{
        name = &plugin_name,
        version = &plugin_version,
        description = &plugin_desc,
        author = &plugin_author,
        supports_linting = true,
        supports_formatting = false,
        supports_analysis = true,
    }
}

// Export function for OLS to call to analyze a file
@(export)
analyze_file :: proc "c"(file_path: ^byte, ast_root: ^ast.Node) -> ^PluginDiagnostic {
    // Convert file path back to Odin string for processing
    file_str := string(file_path)
    
    // Initialize rule registry
    registry := initRuleRegistry()
    registerRule(&registry, C001Rule())
    registerRule(&registry, C002Rule())
    
    // Apply C001 rule
    c001_rule := C001Rule()
    diag := c001_rule.matcher(file_str, ast_root)
    
    if diag.message != "" {
        // Convert diagnostic to plugin format
        plugin_diag := PluginDiagnostic{
            file = cstring(diag.file),
            line = diag.line,
            column = diag.column,
            rule_id = cstring(diag.rule_id),
            tier = cstring(diag.tier),
            message = cstring(diag.message),
            fix = cstring(diag.fix),
            has_fix = diag.has_fix,
        }
        return &plugin_diag
    }
    
    // Apply C002 rule
    c002_rule := C002Rule()
    diag2 := c002_rule.matcher(file_str, ast_root)
    
    if diag2.message != "" {
        // Convert diagnostic to plugin format
        plugin_diag := PluginDiagnostic{
            file = cstring(diag2.file),
            line = diag2.line,
            column = diag2.column,
            rule_id = cstring(diag2.rule_id),
            tier = cstring(diag2.tier),
            message = cstring(diag2.message),
            fix = cstring(diag2.fix),
            has_fix = diag2.has_fix,
        }
        return &plugin_diag
    }
    
    // No diagnostics found
    return nil
}

// Helper function to convert Odin string to C string
// Note: This function cannot be used in "c" calling convention procedures
// because it requires memory allocation (context)
cstring :: proc(s: string) -> ^byte {
    c_str := make([]byte, len(s) + 1)
    for i, char in s {
        c_str[i] = byte(char)
    }
    c_str[len(s)] = 0  // Null-terminate
    return &c_str[0]
}
