#!/bin/bash
# Build tree-sitter libraries and generate bindings for odin-lint

set -e

echo "Building tree-sitter libraries..."

# Build tree-sitter core
cd ffi/tree_sitter/tree-sitter-lib
make clean
make
cd ../../..

# Build Odin grammar
cd ffi/tree_sitter/tree-sitter-odin
make clean
make
cd ../../..

echo "Tree-sitter libraries built successfully!"
echo "Next steps:"
echo "1. Generate Odin bindings (see docs/TREE-SITTER-FFI.md)"
echo "2. Update src/core/tree_sitter.odin to use real FFI"
echo "3. Rebuild odin-lint with: odin build src/core/ -out:odin-lint -extra-linker-flags:\"-Lffi/tree_sitter/tree-sitter-lib -ltree-sitter -Lffi/tree_sitter/tree-sitter-odin -ltree-sitter-odin\""
