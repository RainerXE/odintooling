#!/bin/bash
# Build odin-lint MCP server.
# Output: artifacts/olt-mcp

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Building olt-mcp..."
mkdir -p artifacts

odin build src/mcp \
    -out:artifacts/olt-mcp \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a \
    ffi/sqlite/libsqlite3.a"

echo ""
echo "✅ MCP server build successful!"
echo "   Output: artifacts/olt-mcp"
echo ""
echo "Register in ~/.claude/mcp_servers.json:"
echo '  {'
echo '    "mcpServers": {'
echo '      "olt": {'
echo "        \"command\": \"$(pwd)/artifacts/olt-mcp\","
echo '        "args": []'
echo '      }'
echo '    }'
echo '  }'
