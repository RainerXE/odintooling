package core

// Configuration structure for odin-lint plugin
LintConfig :: struct {
    c001_enabled: bool,
    c001_severity: i32,  // 1=error, 2=warning, 3=info
    c002_enabled: bool,
    c002_severity: i32,
}

// Enhanced OLSPlugin interface for odin-lint
OLSPlugin :: struct {
    magic_number: i32,
    version_major: i32,
    version_minor: i32,
    plugin_type: i32,  // 1 = linter, 2 = formatter, 3 = analyzer
    config_schema: ^byte,  // JSON schema for configuration (pointer to byte)
}

// Initialize config schema at startup
// This would be done in an init procedure if Odin supported it
// For now, we'll use a simple approach

// For now, simplify and use a basic config schema
// We'll implement proper JSON schema later
config_schema_simple: [128]byte = "{\"rules\":{\"C001\":{\"enabled\":true,\"severity\":\"error\"},\"C002\":{\"enabled\":true,\"severity\":\"warning\"}}}"

// Helper function to create plugin instance (not "c" calling convention)
create_plugin_instance :: proc() -> OLSPlugin {
    // Create plugin instance
    plugin := OLSPlugin{}
    plugin.magic_number = 42
    plugin.version_major = 0
    plugin.version_minor = 1
    plugin.plugin_type = 1
    plugin.config_schema = &config_schema_simple
    return plugin
}

// Export the plugin instance
@(export)
get_odin_lint_plugin :: proc "c"() -> OLSPlugin {
    // Create plugin instance
    plugin := OLSPlugin{}
    plugin.magic_number = 42
    plugin.version_major = 0
    plugin.version_minor = 1
    plugin.plugin_type = 1
    plugin.config_schema = &config_schema_simple
    return plugin
}

// Configuration parsing (would be implemented with JSON parser)
// For now, we'll use a simple approach
parse_config :: proc(config_json: ^byte) -> LintConfig {
    // TODO: Implement proper JSON parsing
    // For now, return default configuration
    // Note: Can't use string operations in this context
    return LintConfig{
        c001_enabled = true,
        c001_severity = 1,  // error
        c002_enabled = true,
        c002_severity = 2,  // warning
    }
}

// Export configuration function
@(export)
configure_plugin :: proc "c"(config_json: ^byte) -> bool {
    // Parse and store configuration
    // Note: Can't use complex operations in "c" calling convention
    // For now, just return success
    return true
}

// Export a simple test function
@(export)
test_function :: proc "c"() -> i32 {
    return 42
}
