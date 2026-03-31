#!/bin/bash

echo "Building odin-lint with tree-sitter integration..."

# Build the main application with tree-sitter static library linking
odin build src/core -out:artifacts/odin-lint -define:DEBUG=true \
    -extra-linker-flags:"-Lffi/tree_sitter/tree-sitter-lib/lib/src/macos -ltree-sitter"

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Executable: artifacts/odin-lint"
    echo ""
    echo "To test: ./artifacts/odin-lint --help"
else
    echo "❌ Build failed!"
    echo ""
    echo "If you see linker errors about tree-sitter:"
    echo "1. Make sure you've built the tree-sitter library: ./scripts/build_external_tree_sitter.sh"
    echo "2. Check that libtree-sitter.a exists in ffi/tree_sitter/tree-sitter-lib/lib/src/macos/"
    exit 1
fi