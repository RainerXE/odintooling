#!/bin/bash
# Build olt-mcp MCP server → artifacts/<platform>/olt-mcp

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
OUT="$OUT_DIR/olt-mcp"

echo "Building olt-mcp..."
echo "  Platform: $PLATFORM"
echo "  Output:   $OUT"

odin build "$REPO_ROOT/src/mcp" -out:"$OUT" \
    -extra-linker-flags:"$REPO_ROOT/ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    $REPO_ROOT/ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    $REPO_ROOT/ffi/sqlite/libsqlite3.a"

echo "✅ MCP server build successful!"
echo "   Output: $OUT"
echo ""
echo "Register in ~/.claude/mcp_servers.json:"
echo "  { \"mcpServers\": { \"olt\": { \"command\": \"$OUT\", \"args\": [] } } }"
