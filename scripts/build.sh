#!/bin/bash
# Build olt → artifacts/<platform>/olt
# Single binary: CLI + MCP server + LSP proxy (dispatched via argv[0] or subcommand)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Detect platform
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
OUT="$OUT_DIR/olt"

# SQLite is linked via vendor/odin-sqlite3's named foreign import, which
# resolves to artifacts/libsqlite3.a relative to that package. Build it from
# the submodule's vendored amalgamation on first use (no network needed).
SQLITE_PKG="$REPO_ROOT/vendor/odin-sqlite3"
if [ ! -f "$SQLITE_PKG/artifacts/libsqlite3.a" ]; then
    echo "Building libsqlite3.a (vendor/odin-sqlite3)..."
    (cd "$SQLITE_PKG" && ./build.sh)
fi

echo "Building olt (Odin Language Tools)..."
echo "  Platform: $PLATFORM"
echo "  Output:   $OUT"

odin build "$REPO_ROOT/src" -out:"$OUT" \
    -extra-linker-flags:"$REPO_ROOT/ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    $REPO_ROOT/ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a"
# sqlite3 comes in via vendor/odin-sqlite3's named foreign import (its
# artifacts/libsqlite3.a), not via -extra-linker-flags.

echo "✅ Build successful!"
echo "Executable: $OUT"
echo ""
echo "To test:       $OUT --help"
echo "MCP mode:      $OUT mcp"
echo "LSP mode:      $OUT lsp     (or symlink: ols → olt)"
