#!/bin/bash
# DEPRECATED: olt-lsp is now part of the unified olt binary.
# Use ./scripts/build.sh to build olt, then run as:
#   olt lsp                  (subcommand)
#   olt --install            (creates ols and olt-lsp symlinks if desired)
#
# This script delegates to build.sh for backward compatibility.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Note: build_lsp.sh is deprecated — LSP proxy is now built into olt."
echo "      Delegating to build.sh..."
echo ""

exec "$SCRIPT_DIR/build.sh" "$@"
