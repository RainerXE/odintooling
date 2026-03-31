package core

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "base:runtime"

// cstring is a C-compatible string (^byte)
cstring :: ^byte

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

// File analysis (defined in plugin_main.odin)

// Convert Diagnostic to PluginDiagnostic (C-compatible)
// TODO: Implement properly (requires string to ^byte conversion)

// Configuration schema
odin_lint_get_config_schema :: proc "c" () -> ^byte {
    // TODO: Return proper cstring (^byte)
    return nil
}

// Configuration validation
odin_lint_validate_config :: proc "c" (config: rawptr) -> bool {
    return true
}

