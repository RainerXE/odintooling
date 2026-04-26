#!/bin/bash
# Build olt CLI → artifacts/<platform>/olt

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

echo "Building olt (Odin Language Tools)..."
echo "  Platform: $PLATFORM"
echo "  Output:   $OUT"

odin build "$REPO_ROOT/src/core" -out:"$OUT" \
    -extra-linker-flags:"$REPO_ROOT/ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    $REPO_ROOT/ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    $REPO_ROOT/ffi/sqlite/libsqlite3.a"

echo "✅ Build successful!"
echo "Executable: $OUT"
echo ""
echo "To test: $OUT --help"
