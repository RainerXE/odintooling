package build

import "core:fmt"
import "core:os"

main :: proc() {
    fmt.println("Building odin-lint plugin as shared library...")
    
    // Build the plugin as a shared library
    // We need to build the plugin integration code
    err := os.exec("odin", "build", "src/integrations/ols", 
                    "-out:artifacts/odin_lint_plugin", 
                    "-shared",
                    "-define:DEBUG=true")
    
    if err != 0 {
        fmt.fprintln(os.stderr, "Plugin build failed with exit code:", err)
        os.exit(1)
    }
    
    fmt.println("Plugin build successful!")
    fmt.println("Shared library created at: artifacts/odin_lint_plugin.so (or .dll/.dylib)")
    
    os.exit(0)
}