#!/bin/bash
# Build olt-lsp — LSP proxy server that wraps vanilla OLS.
# Output: artifacts/olt-lsp
#
# Editor config (VS Code):
#   "odin.languageServer.path": "/path/to/artifacts/olt-lsp"
#
# OLS path config (olt.toml):
#   [tools]
#   ols_path = "/path/to/ols"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Building olt-lsp..."
mkdir -p artifacts

odin build src/lsp \
    -out:artifacts/olt-lsp \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    ffi/sqlite/libsqlite3.a"

echo ""
echo "✅ LSP proxy build successful!"
echo "   Output: artifacts/olt-lsp"
echo ""
echo "Configure your editor to use olt-lsp as the Odin language server."
echo "Example VS Code settings.json:"
echo '  "odin.languageServer.path": "'"$(pwd)/artifacts/olt-lsp"'"'
echo ""
echo "OLS binary path (optional, defaults to PATH lookup):"
echo "  Add to olt.toml:"
echo "    [tools]"
echo "    ols_path = \"/path/to/ols\""
echo ""
echo "Vanilla OLS: https://github.com/DanielGavin/ols"
