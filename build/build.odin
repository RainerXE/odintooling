package build

import "core:fmt"
import "core:os"
import "core:c/libc"

// Directory constants (relative to project root)
SRC_DIR :: "src"
ARTIFACTS_DIR :: "artifacts"
FFI_DIR :: "ffi"
TREE_SITTER_LIB_DIR :: FFI_DIR + "/tree_sitter/tree-sitter-lib"

main :: proc() {
    fmt.println("🚀 Building odin-lint with tree-sitter integration...")
    
    // Build command with tree-sitter linking
    build_cmd := fmt.tprintf(
        "odin build %s/core -out:%s/odin-lint -define:DEBUG=true " +
        "-extra-linker-flags:\"-L%s/lib/src/macos -ltree-sitter\"",
        SRC_DIR,
        ARTIFACTS_DIR,
        TREE_SITTER_LIB_DIR
    )
    
    fmt.println("🔨 Executing:", build_cmd)
    
    // Execute the build
    exit_code := libc.system(strings.clone_to_cstring(build_cmd))
    
    if exit_code == 0 {
        fmt.println("✅ Build successful!")
        fmt.println("📁 Executable: artifacts/odin-lint")
        fmt.println("🧪 Test: ./artifacts/odin-lint <file>")
    } else {
        fmt.println("❌ Build failed with exit code:", exit_code)
        fmt.println("\nTroubleshooting:")
        fmt.println("1. Ensure tree-sitter library is built:")
        fmt.println("   ./scripts/build_external_tree_sitter.sh")
        fmt.println("2. Check library exists:")
        fmt.println("   ffi/tree_sitter/tree-sitter-lib/lib/src/macos/libtree-sitter.a")
        fmt.println("3. Try building without tree-sitter first:")
        fmt.println("   odin run build -define:NO_TREE_SITTER=true")
    }
    
    os.exit(exit_code)
}