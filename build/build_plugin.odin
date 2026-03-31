package build

import "core:fmt"
import "core:os"
import "core:c/libc"
import "core:strings"

// build_plugin builds the odin-lint plugin as a shared library
// This is used when integrating with OLS (Odin Language Server)
// Returns: exit code (0 for success)
build_plugin :: proc() -> int {
    fmt.println("🔌 Building odin-lint plugin as shared library...")
    
    // Build the plugin as a shared library
    build_cmd := fmt.tprintf(
        "odin build %s/integrations/ols -out:%s/odin_lint_plugin -shared -define:DEBUG=true",
        "src",
        "artifacts"
    )
    
    fmt.println("🔨 Executing:", build_cmd)
    
    // Execute the build
    exit_code := libc.system(strings.clone_to_cstring(build_cmd))
    
    if exit_code == 0 {
        fmt.println("✅ Plugin build successful!")
        fmt.println("📁 Output: artifacts/odin_lint_plugin")
    } else {
        fmt.println("❌ Plugin build failed with exit code:", exit_code)
    }
    
    return exit_code
}