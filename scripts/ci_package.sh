#!/usr/bin/env bash
# ci_package.sh <version> <dist-dir> <out-dir> — one archive per platform from the downloaded CI artifacts.
#
#   <dist-dir>/macos-arm64/olt, <dist-dir>/linux-x86_64/olt, <dist-dir>/windows-x86_64/olt.exe
#   -> <out-dir>/olt-<version>-macos-arm64.tar.gz, ...-linux-x86_64.tar.gz, ...-windows-x86_64.zip
#
# Each archive holds olt, olt-mcp and olt-lsp. They are the same binary: argv[0] picks the mode, so on macOS and Linux the
# last two are symlinks. Artifacts lose the executable bit when they are uploaded and downloaded, so it is set here.
# A platform whose artifact is missing is skipped. Used by .github/workflows/build.yml.
set -euo pipefail

VERSION="${1:?usage: ci_package.sh <version> <dist-dir> <out-dir>}"
DIST="$(cd "${2:?usage: ci_package.sh <version> <dist-dir> <out-dir>}" && pwd)"
mkdir -p "${3:?usage: ci_package.sh <version> <dist-dir> <out-dir>}"
OUT="$(cd "$3" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for plat in macos-arm64 linux-x86_64; do
  if [ ! -f "$DIST/$plat/olt" ]; then echo "skipping $plat: no $DIST/$plat/olt"; continue; fi
  name="olt-$VERSION-$plat"
  mkdir -p "$STAGE/$name"
  cp "$DIST/$plat/olt" "$STAGE/$name/olt"
  chmod +x "$STAGE/$name/olt"
  ln -s olt "$STAGE/$name/olt-mcp"
  ln -s olt "$STAGE/$name/olt-lsp"
  tar czf "$OUT/$name.tar.gz" -C "$STAGE" "$name"
done

if [ -f "$DIST/windows-x86_64/olt.exe" ]; then
  name="olt-$VERSION-windows-x86_64"
  mkdir -p "$STAGE/$name"
  for exe in olt.exe olt-mcp.exe olt-lsp.exe; do cp "$DIST/windows-x86_64/olt.exe" "$STAGE/$name/$exe"; done
  (cd "$STAGE" && zip -qr "$OUT/$name.zip" "$name")
else
  echo "skipping windows-x86_64: no $DIST/windows-x86_64/olt.exe"
fi

ls -l "$OUT"
