#!/usr/bin/env bash
# build_linux_podman_x86.sh
# Cross-compile olt for Linux x86_64 via Podman + QEMU emulation on Apple Silicon.
# NOTE: Runs through QEMU — expect 5-10x slower than the ARM64 Podman build.
# Output: artifacts/linux-x86_64-podman/

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Launching Linux x86_64 container (QEMU emulation — this will be slow)..."
podman run --platform linux/amd64 \
    -v "$REPO:/build" \
    ubuntu:24.04 \
    bash /build/scripts/_build_linux_inner.sh podman
