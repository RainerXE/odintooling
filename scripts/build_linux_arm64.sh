#!/usr/bin/env bash
# build_linux_arm64.sh
# Build olt natively on a Linux ARM64 machine (no emulation, no container).
# Run this script directly on your Linux ARM64 hardware or VM.
# Output: artifacts/linux-arm64/

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BUILD="$(cd "$SCRIPT_DIR/.." && pwd)"

bash "$SCRIPT_DIR/_build_linux_inner.sh"
