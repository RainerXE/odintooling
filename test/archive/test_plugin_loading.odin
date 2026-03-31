package main

import "core:fmt"
import "core:dynlib"
import "core:os"

main :: proc() {
    fmt.println("Testing plugin loading...")
    
    // Try to load our test plugin
    plugin_path := "test_plugin.dylib"
    
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
    
    // Try to get the get_plugin_instance function
    // Note: Odin exports it with the mangled name _get_plugin_instance
    get_instance_func, found := dynlib.symbol_address(library, "_get_plugin_instance")
    if !found {
        fmt.println("Failed to find _get_plugin_instance function")
        dynlib.unload_library(library)
        os.exit(1)
    }
    
    fmt.println("Successfully found _get_plugin_instance function")
    
    fmt.println("Successfully found get_plugin_instance function")
    
    // Try to call the function (this would require proper FFI setup)
    fmt.println("Plugin loading test successful!")
    
    // Unload the library
    dynlib.unload_library(library)
    fmt.println("Plugin unloaded successfully")
}