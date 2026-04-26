#!/bin/bash
# Build olt-lsp LSP proxy → artifacts/<platform>/olt-lsp
# Editor points to olt-lsp; it wraps vanilla OLS and injects olt diagnostics.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$OS/$ARCH" in
  darwin/arm64)  PLATFORM="macos-arm64"  ;;
  darwin/x86_64) PLATFORM="macos-x86_64" ;;
  linux/aarch64) PLATFORM="linux-arm64"  ;;
  linux/x86_64)  PLATFORM="linux-x86_64" ;;
  *)             PLATFORM="$OS-$ARCH"    ;;
esac

OUT_DIR="$REPO_ROOT/artifacts/$PLATFORM"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/olt-lsp"

echo "Building olt-lsp..."
echo "  Platform: $PLATFORM"
echo "  Output:   $OUT"

odin build "$REPO_ROOT/src/lsp" -out:"$OUT" \
    -extra-linker-flags:"$REPO_ROOT/ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    $REPO_ROOT/ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    $REPO_ROOT/ffi/sqlite/libsqlite3.a"

echo "✅ LSP proxy build successful!"
echo "   Output: $OUT"
echo ""
echo "Configure your editor to use olt-lsp as the Odin language server."
echo "  VS Code settings.json:  \"odin.languageServer.path\": \"$OUT\""
echo ""
echo "OLS path (optional — defaults to 'ols' in PATH):"
echo "  Add to olt.toml:  [tools]  ols_path = \"/path/to/ols\""
echo "  Vanilla OLS: https://github.com/DanielGavin/ols"
