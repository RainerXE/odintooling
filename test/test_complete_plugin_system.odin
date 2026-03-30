package main

import "core:fmt"
import "core:dynlib"
import "core:os"

// Test the complete plugin system
main :: proc() {
    fmt.println("=== Complete OLS Plugin System Test ===")
    
    // Test 1: Simple plugin (baseline)
    fmt.println("\n1. Testing simple_test_plugin.dylib...")
    if test_plugin("simple_test_plugin.dylib", "get_simple_plugin") {
        fmt.println("✅ Simple plugin test PASSED")
    } else {
        fmt.println("❌ Simple plugin test FAILED")
        return
    }
    
    // Test 2: Odin-lint plugin (main target)
    fmt.println("\n2. Testing odin-lint-plugin.dylib...")
    if test_plugin("odin-lint-plugin.dylib", "get_odin_lint_plugin") {
        fmt.println("✅ Odin-lint plugin test PASSED")
    } else {
        fmt.println("❌ Odin-lint plugin test FAILED")
        return
    }
    
    fmt.println("\n=== All Tests PASSED ===")
    fmt.println("🎉 Plugin system is fully functional!")
    fmt.println("\nNext steps:")
    fmt.println("- Integrate with OLS plugin manager")
    fmt.println("- Implement full linting analysis")
    fmt.println("- Test with real Odin code files")
}

// Test a single plugin
test_plugin :: proc(plugin_path: string, symbol_name: string) -> bool {
    fmt.printf("  Loading: %s... ", plugin_path)
    
    library, ok := dynlib.load_library(plugin_path)
    if !ok {
        fmt.println("FAILED")
        error_msg := dynlib.last_error()
        if error_msg != "" {
            fmt.printf("  Error: %s\n", error_msg)
        }
        return false
    }
    
    // Try to find the symbol (without underscore prefix)
    symbol_func, found := dynlib.symbol_address(library, symbol_name)
    if !found {
        fmt.println("FAILED")
        fmt.printf("  Symbol '%s' not found\n", symbol_name)
        dynlib.unload_library(library)
        return false
    }
    
    fmt.println("SUCCESS")
    
    // Test calling the function
    if symbol_name == "get_simple_plugin" {
        test_proc := cast(proc "c"() -> SimplePlugin)(symbol_func)
        plugin := test_proc()
        fmt.printf("  Plugin data: magic=%d, version=%d.%d, type=%d\n",
                  plugin.magic_number, plugin.version_major, plugin.version_minor, plugin.plugin_type)
    } else if symbol_name == "get_odin_lint_plugin" {
        test_proc := cast(proc "c"() -> OLSPlugin)(symbol_func)
        plugin := test_proc()
        fmt.printf("  Plugin data: magic=0x%X, version=%d.%d, type=%d\n",
                  plugin.magic_number, plugin.version_major, plugin.version_minor, plugin.plugin_type)
    }
    
    dynlib.unload_library(library)
    return true
}

// Plugin struct definitions
SimplePlugin :: struct {
    magic_number: i32,
    version_major: i32,
    version_minor: i32,
    plugin_type: i32,
}

OLSPlugin :: struct {
    magic_number: i32,
    version_major: i32,
    version_minor: i32,
    plugin_type: i32,
}