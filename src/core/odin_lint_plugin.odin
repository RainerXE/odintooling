package core

import "core:fmt"
import "core:mem"
import "core:odin/ast"

// PluginDiagnostic represents a linting diagnostic (C-compatible)
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

// Plugin initialization
odin_lint_initialize :: proc "c" (config: rawptr) -> bool {
    fmt.println("Initializing odin-lint plugin")
    return true
}

// Plugin shutdown
odin_lint_shutdown :: proc "c" () {
    fmt.println("Shutting down odin-lint plugin")
}

// File analysis
odin_lint_analyze_file :: proc "c" (file_path: ^byte, ast_root: rawptr) -> rawptr {
    file_str := string(file_path)
    ast_node := cast(^ast.Node)(ast_root)
    
    fmt.printf("Analyzing file: %s\n", file_str)
    
    // Initialize rule registry
    registry := initRuleRegistry()
    registerRule(&registry, C001Rule())
    registerRule(&registry, C002Rule())
    
    // Apply C001 rule
    c001_rule := C001Rule()
    diag := c001_rule.matcher(file_str, ast_node)
    
    if diag.message != "" {
        return convert_to_plugin_diagnostic(diag)
    }
    
    // Apply C002 rule
    c002_rule := C002Rule()
    diag2 := c002_rule.matcher(file_str, ast_node)
    
    if diag2.message != "" {
        return convert_to_plugin_diagnostic(diag2)
    }
    
    return nil
}

// Convert Diagnostic to PluginDiagnostic (C-compatible)
convert_to_plugin_diagnostic :: proc(diag: Diagnostic) -> ^PluginDiagnostic {
    plugin_diag := new(PluginDiagnostic)
    plugin_diag.file = cstring(diag.file)
    plugin_diag.line = diag.line
    plugin_diag.column = diag.column
    plugin_diag.rule_id = cstring(diag.rule_id)
    plugin_diag.tier = cstring(diag.tier)
    plugin_diag.message = cstring(diag.message)
    plugin_diag.fix = cstring(diag.fix)
    plugin_diag.has_fix = diag.has_fix
    return plugin_diag
}

// Configuration schema
odin_lint_get_config_schema :: proc "c" () -> ^byte {
    schema := `{
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
    return cstring(schema)
}

// Configuration validation
odin_lint_validate_config :: proc "c" (config: rawptr) -> bool {
    return true
}

// Helper: Convert Odin string to C string (null-terminated)
cstring :: proc(s: string) -> ^byte {
    c_str := make([]byte, len(s) + 1)
    for i, char in s {
        c_str[i] = byte(char)
    }
    c_str[len(s)] = 0  // Null-terminate
    return &c_str[0]
}
