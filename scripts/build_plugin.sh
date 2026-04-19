#!/bin/bash
# Build odin-lint as an OLS plugin shared library.
# Output: artifacts/odin-lint-plugin.dylib  (macOS)
#         artifacts/odin-lint-plugin.so      (Linux)
#         artifacts/odin-lint-plugin.dll     (Windows)

set -e

echo "Building odin-lint OLS plugin..."

mkdir -p artifacts

odin build src/core \
    -out:artifacts/odin-lint-plugin \
    -build-mode:shared \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    ffi/sqlite/libsqlite3.a"

# Rename to canonical .dylib/.so extension for clarity
case "$(uname -s)" in
    Darwin)
        # Odin emits .dylib on macOS
        PLUGIN_OUT="artifacts/odin-lint-plugin.dylib"
        ;;
    Linux)
        PLUGIN_OUT="artifacts/odin-lint-plugin.so"
        ;;
    *)
        PLUGIN_OUT="artifacts/odin-lint-plugin"
        ;;
esac

echo ""
echo "✅ Plugin build successful!"
echo "   Output: ${PLUGIN_OUT}"
echo ""
echo "Register in ols.json:"
echo '  {'
echo '    "plugins": ['
echo "      { \"name\": \"odin-lint\", \"path\": \"$(pwd)/${PLUGIN_OUT}\", \"enabled\": true }"
echo '    ]'
echo '  }'
