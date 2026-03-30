package core

import "core:fmt"
import "core:mem"
import "core:odin/ast"

// OLSPlugin represents the interface that all OLS plugins must implement
OLSPlugin :: struct {
    // Plugin metadata
    name:        string,
    version:     string,
    description: string,
    author:      string,
    
    // Plugin lifecycle functions
    initialize:   proc(plugin: ^OLSPlugin, config: rawptr) -> bool,
    shutdown:     proc(plugin: ^OLSPlugin),
    
    // Analysis functions
    analyze_file: proc(plugin: ^OLSPlugin, file_path: string, ast_root: ^ast.Node) -> []Diagnostic,
    
    // Configuration
    get_config_schema: proc(plugin: ^OLSPlugin) -> string,
    validate_config: proc(plugin: ^OLSPlugin, config: rawptr) -> bool,
}

// Export the plugin interface for dynamic loading
// This will be called by OLS to get the plugin instance
get_plugin_instance :: proc() -> OLSPlugin {
    return OLSPlugin{
        name = "odin-lint",
        version = "0.1.0",
        description = "Static analysis linter for Odin code",
        author = "RuiShin Projects",
        
        initialize = plugin_initialize,
        shutdown = plugin_shutdown,
        analyze_file = plugin_analyze_file,
        get_config_schema = plugin_get_config_schema,
        validate_config = plugin_validate_config,
    }
}

// Plugin initialization
plugin_initialize :: proc(plugin: ^OLSPlugin, config: rawptr) -> bool {
    fmt.println("Initializing odin-lint plugin")
    // TODO: Parse configuration
    return true
}

// Plugin shutdown
plugin_shutdown :: proc(plugin: ^OLSPlugin) {
    fmt.println("Shutting down odin-lint plugin")
    // TODO: Clean up resources
}

// File analysis
plugin_analyze_file :: proc(plugin: ^OLSPlugin, file_path: string, ast_root: ^ast.Node) -> []Diagnostic {
    fmt.printf("Analyzing file: %s\n", file_path)
    
    diagnostics := make([]Diagnostic, 0)
    
    // Initialize rule registry
    registry := initRuleRegistry()
    registerRule(&registry, C001Rule())
    registerRule(&registry, C002Rule())
    
    // Apply C001 rule
    c001_rule := C001Rule()
    diag := c001_rule.matcher(file_path, ast_root)
    if diag.message != "" {
        diagnostics.append(diag)
    }
    
    // Apply C002 rule
    c002_rule := C002Rule()
    diag2 := c002_rule.matcher(file_path, ast_root)
    if diag2.message != "" {
        diagnostics.append(diag2)
    }
    
    return diagnostics
}

// Configuration schema
plugin_get_config_schema :: proc(plugin: ^OLSPlugin) -> string {
    return `{
        "type": "object",
        "properties": {
            "rules": {
                "type": "object",
                "properties": {
                    "C001": {
                        "type": "object",
                        "properties": {
                            "enabled": {"type": "boolean"},
                            "severity": {"type": "string", "enum": ["error", "warning", "info"]}
                        }
                    },
                    "C002": {
                        "type": "object",
                        "properties": {
                            "enabled": {"type": "boolean"},
                            "severity": {"type": "string", "enum": ["error", "warning", "info"]}
                        }
                    }
                }
            }
        }
    }`
}

// Configuration validation
plugin_validate_config :: proc(plugin: ^OLSPlugin, config: rawptr) -> bool {
    // TODO: Implement proper configuration validation
    return true
}
