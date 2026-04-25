#!/bin/bash

echo "Building olt (Odin Language Tools)..."

odin build src/core -out:artifacts/olt \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    ffi/sqlite/libsqlite3.a"

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Executable: artifacts/olt"
    echo ""
    echo "To test: ./artifacts/olt --help"
else
    echo "❌ Build failed!"
    echo ""
    echo "If you see linker errors about tree-sitter:"
    echo "1. Make sure you've built the tree-sitter library: ./scripts/build_external_tree_sitter.sh"
    echo "2. Check that libtree-sitter.a exists in ffi/tree_sitter/tree-sitter-lib/lib/src/macos/"
    exit 1
fi
