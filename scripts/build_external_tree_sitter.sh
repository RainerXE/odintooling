#!/bin/bash
# Build external tree-sitter library
# NOTE: This script builds the tree-sitter C library that odin-lint depends on
# Run from project root: ./scripts/build_external_tree_sitter.sh

set -e

echo "🔧 Building external tree-sitter library..."

# Build tree-sitter core library
cd ffi/tree_sitter/tree-sitter-lib || { echo "Failed to find tree-sitter-lib directory"; exit 1; }
make clean
make
cd ../..

echo "✅ External tree-sitter library built successfully!"
echo ""
echo "📁 Output:"
echo "   - Static library: ffi/tree_sitter/tree-sitter-lib/lib/src/macos/libtree-sitter.a"
echo "   - Dynamic library: ffi/tree_sitter/tree-sitter-lib/libtree-sitter.dylib"
echo ""
echo "🔗 Next: Build odin-lint using:"
echo "   odin run build"