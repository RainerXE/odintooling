#!/bin/bash
# DEPRECATED: olt-mcp is now part of the unified olt binary.
# Use ./scripts/build.sh to build olt, then run as:
#   olt mcp                  (subcommand)
#   olt --install            (creates olt-mcp symlink if desired)
#
# This script delegates to build.sh for backward compatibility.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Note: build_mcp.sh is deprecated — MCP is now built into olt."
echo "      Delegating to build.sh..."
echo ""

exec "$SCRIPT_DIR/build.sh" "$@"
