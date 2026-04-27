#!/usr/bin/env bash
# build_linux_podman_arm64.sh
# Cross-compile olt for Linux ARM64 via Podman on Apple Silicon (native speed).
# Output: artifacts/linux-arm64-podman/

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Launching Linux ARM64 container (native on Apple Silicon)..."
podman run --platform linux/arm64 \
    -v "$REPO:/build" \
    ubuntu:24.04 \
    bash /build/scripts/_build_linux_inner.sh podman
