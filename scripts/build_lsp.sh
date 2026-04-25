#!/bin/bash
# Build odin-lint-lsp — LSP proxy server that wraps vanilla OLS.
# Output: artifacts/odin-lint-lsp
#
# Editor config (VS Code):
#   "odin.languageServer.path": "/path/to/artifacts/odin-lint-lsp"
#
# OLS path config (odin-lint.toml):
#   [tools]
#   ols_path = "/path/to/ols"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Building odin-lint-lsp..."
mkdir -p artifacts

odin build src/lsp \
    -out:artifacts/odin-lint-lsp \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    ffi/sqlite/libsqlite3.a"

echo ""
echo "✅ LSP proxy build successful!"
echo "   Output: artifacts/odin-lint-lsp"
echo ""
echo "Configure your editor to use odin-lint-lsp as the Odin language server."
echo "Example VS Code settings.json:"
echo '  "odin.languageServer.path": "'"$(pwd)/artifacts/odin-lint-lsp"'"'
echo ""
echo "OLS binary path (optional, defaults to PATH lookup):"
echo "  Add to odin-lint.toml:"
echo "    [tools]"
echo "    ols_path = \"/path/to/ols\""
echo ""
echo "Vanilla OLS: https://github.com/DanielGavin/ols"
