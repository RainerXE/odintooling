package main

import "core:fmt"
import "core:dynlib"
import "core:os"

// Define the SimplePlugin struct to match what's in the plugin
SimplePlugin :: struct {
    magic_number: i32,
    version_major: i32,
    version_minor: i32,
}

main :: proc() {
    fmt.println("Testing simple plugin loading...")
    
    // Try to load our simple test plugin
    plugin_path := "simple_test_plugin.dylib"
    
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
    
    // Try to get the get_simple_plugin function
    // Try the mangled name first
    get_plugin_func, found := dynlib.symbol_address(library, "_get_simple_plugin")
    if !found {
        // Try without underscore prefix
        get_plugin_func, found = dynlib.symbol_address(library, "get_simple_plugin")
        if !found {
            fmt.println("Failed to find get_simple_plugin function")
            dynlib.unload_library(library)
            os.exit(1)
        }
    }
    
    fmt.println("Successfully found _get_simple_plugin function")
    
    // Cast the function pointer to a callable procedure
    get_plugin_proc := cast(proc "c"() -> SimplePlugin)(get_plugin_func)
    
    // Call the function
    plugin := get_plugin_proc()
    
    fmt.printf("Plugin loaded successfully!\n")
    fmt.printf("Magic number: %d\n", plugin.magic_number)
    fmt.printf("Version: %d.%d\n", plugin.version_major, plugin.version_minor)
    
    // Unload the library
    dynlib.unload_library(library)
    fmt.println("Plugin unloaded successfully")
    
    fmt.println("Simple plugin loading test successful!")
}