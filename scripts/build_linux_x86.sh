#!/usr/bin/env bash
# build_linux_x86.sh
# Build olt natively on a Linux x86_64 machine (no emulation, no container).
# Run this script directly on your Linux x86_64 hardware or VM.
# Output: artifacts/linux-x86_64/

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BUILD="$(cd "$SCRIPT_DIR/.." && pwd)"

bash "$SCRIPT_DIR/_build_linux_inner.sh"
