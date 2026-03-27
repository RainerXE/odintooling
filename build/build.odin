package build

import "core:fmt"
import "core:os"

main :: proc() {
    fmt.println("Building odin-lint...")
    
    // Build the main application
    err := os.system("odin", "build", "src/core", "-out:artifacts/odin-lint", "-define:DEBUG=true")
    
    if err != 0 {
        fmt.fprintln(os.stderr, "Build failed with exit code:", err)
        os.exit(1)
    }
    
    fmt.println("Build successful!")
    
    os.exit(0)
}