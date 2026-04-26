#!/usr/bin/env bash
# _platform.sh — sourced by other scripts to set OLT_BINARY and PLATFORM.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_platform.sh"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$OS/$ARCH" in
  darwin/arm64)  PLATFORM="macos-arm64"  ;;
  darwin/x86_64) PLATFORM="macos-x86_64" ;;
  linux/aarch64) PLATFORM="linux-arm64"  ;;
  linux/x86_64)  PLATFORM="linux-x86_64" ;;
  *)             PLATFORM="$OS-$ARCH"    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLT_BINARY="$REPO_ROOT/artifacts/$PLATFORM/olt"

if [ ! -f "$OLT_BINARY" ]; then
  echo "error: binary not found at $OLT_BINARY — run ./scripts/build.sh first" >&2
  exit 1
fi
