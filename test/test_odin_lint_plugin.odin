package main

import "core:fmt"
import "core:dynlib"
import "core:os"

// Define the OLSPlugin struct to match what's in the plugin
OLSPlugin :: struct {
    magic_number: i32,
    version_major: i32,
    version_minor: i32,
    plugin_type: i32,  // 1 = linter, 2 = formatter, 3 = analyzer
}

main :: proc() {
    fmt.println("Testing odin-lint plugin loading...")
    
    // Try to load our odin-lint plugin
    plugin_path := "odin-lint-plugin.dylib"
    
    fmt.printf("Attempting to load plugin: %s\n", plugin_path)
    
    library, ok := dynlib.load_library(plugin_path)
    if !ok {
        fmt.printf("Failed to load plugin: %s\n", plugin_path)
        error_msg := dynlib.last_error()
        if error_msg != "" {
            fmt.printf("Error: %s\n", error_msg)
        } else {
            fmt.println("Error: Unknown loading error")
        }
        os.exit(1)
    }
    
    fmt.printf("Successfully loaded plugin: %s\n", plugin_path)
    
    // Try to get the get_odin_lint_plugin function
    // Note: Use symbol name WITHOUT underscore prefix (Odin handles mangling)
    get_plugin_func, found := dynlib.symbol_address(library, "get_odin_lint_plugin")
    if !found {
        fmt.println("Failed to find get_odin_lint_plugin function")
        dynlib.unload_library(library)
        os.exit(1)
    }
    
    fmt.println("Successfully found _get_odin_lint_plugin function")
    
    // Cast the function pointer to a callable procedure
    get_plugin_proc := cast(proc "c"() -> OLSPlugin)(get_plugin_func)
    
    // Call the function
    plugin := get_plugin_proc()
    
    fmt.printf("Odin-lint plugin loaded successfully!\n")
    fmt.printf("Magic number: 0x%X\n", plugin.magic_number)
    fmt.printf("Version: %d.%d\n", plugin.version_major, plugin.version_minor)
    plugin_type_str := "unknown"
    if plugin.plugin_type == 1 {
        plugin_type_str = "linter"
    }
    fmt.printf("Plugin type: %d (%s)\n", plugin.plugin_type, plugin_type_str)
    
    // Test the test_function as well
    test_func, test_found := dynlib.symbol_address(library, "test_function")
    if test_found {
        test_proc := cast(proc "c"() -> i32)(test_func)
        result := test_proc()
        fmt.printf("Test function returned: %d\n", result)
    }
    
    // Unload the library
    dynlib.unload_library(library)
    fmt.println("Plugin unloaded successfully")
    
    fmt.println("Odin-lint plugin loading test successful!")
}