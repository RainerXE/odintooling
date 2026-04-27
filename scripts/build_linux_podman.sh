#!/usr/bin/env bash
# build_linux.sh — builds olt, olt-mcp, olt-lsp for Linux ARM64.
# Run INSIDE a Linux ARM64 container:
#
#   podman run --platform linux/arm64 \
#     -v "$(pwd):/build" ubuntu:24.04 \
#     bash /build/scripts/build_linux.sh
#
# Output: /build/artifacts/linux-arm64-podman/{olt,olt-mcp,olt-lsp}

set -euo pipefail

BUILD="/build"
PLATFORM="linux-arm64-podman"
OUT="$BUILD/artifacts/$PLATFORM"
LIBS="/tmp/olt-libs"

mkdir -p "$OUT" "$LIBS"

# ── 1. System dependencies ─────────────────────────────────────────────────────
echo "--- Installing build dependencies ---"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gcc clang make wget curl git xz-utils unzip ca-certificates

# ── 2. libtree-sitter.a ───────────────────────────────────────────────────────
echo "--- Building libtree-sitter ---"
TS_LIB="$BUILD/ffi/tree_sitter/tree-sitter-lib/lib"
gcc -O2 -fPIC -std=c11 \
    -I"$TS_LIB/include" -I"$TS_LIB/src" -I"$TS_LIB/src/wasm" \
    -c "$TS_LIB/src/lib.c" \
    -o "$LIBS/libtree-sitter.o"
ar rcs "$LIBS/libtree-sitter.a" "$LIBS/libtree-sitter.o"
echo "  ✓ libtree-sitter.a"

# ── 3. libtree-sitter-odin.a ──────────────────────────────────────────────────
echo "--- Building libtree-sitter-odin ---"
gcc -O2 -fPIC -std=c11 \
    -I"$TS_LIB/include" -I"$TS_LIB/src" \
    -c "$BUILD/ffi/tree_sitter/tree-sitter-odin/src/parser.c" \
    -o "$LIBS/ts-odin-parser.o"
gcc -O2 -fPIC -std=c11 \
    -I"$TS_LIB/include" -I"$TS_LIB/src" \
    -c "$BUILD/ffi/tree_sitter/tree-sitter-odin/src/scanner.c" \
    -o "$LIBS/ts-odin-scanner.o"
ar rcs "$LIBS/libtree-sitter-odin.a" "$LIBS/ts-odin-parser.o" "$LIBS/ts-odin-scanner.o"
echo "  ✓ libtree-sitter-odin.a"

# ── 4. libsqlite3.a ───────────────────────────────────────────────────────────
echo "--- Building libsqlite3 ---"
SQLITE_VER="3460100"
SQLITE_URL="https://sqlite.org/2024/sqlite-amalgamation-${SQLITE_VER}.zip"
wget -q "$SQLITE_URL" -O /tmp/sqlite.zip
cd /tmp && unzip -q sqlite.zip
gcc -O2 -fPIC \
    -DSQLITE_THREADSAFE=0 \
    -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
    -c "/tmp/sqlite-amalgamation-${SQLITE_VER}/sqlite3.c" \
    -o "$LIBS/sqlite3.o"
ar rcs "$LIBS/libsqlite3.a" "$LIBS/sqlite3.o"
cd "$BUILD"
echo "  ✓ libsqlite3.a"

# ── 5. Install Odin for Linux ARM64 ───────────────────────────────────────────
echo "--- Installing Odin ---"
ODIN_TAG="dev-2026-04"
ODIN_URL="https://github.com/odin-lang/Odin/releases/download/${ODIN_TAG}/odin-linux-arm64-${ODIN_TAG}.tar.gz"
wget -q "$ODIN_URL" -O /tmp/odin.tar.gz
mkdir -p /opt/odin
tar xzf /tmp/odin.tar.gz -C /opt/odin --strip-components=1
export PATH="/opt/odin:$PATH"
odin version
echo "  ✓ Odin installed"

# ── 6. Build olt, olt-mcp, olt-lsp ────────────────────────────────────────────
LINKER_FLAGS="$LIBS/libtree-sitter.a $LIBS/libtree-sitter-odin.a $LIBS/libsqlite3.a"

echo "--- Building olt ---"
odin build "$BUILD/src/core" \
    -out:"$OUT/olt" \
    -extra-linker-flags:"$LINKER_FLAGS"
echo "  ✓ olt"

echo "--- Building olt-mcp ---"
odin build "$BUILD/src/mcp" \
    -out:"$OUT/olt-mcp" \
    -extra-linker-flags:"$LINKER_FLAGS"
echo "  ✓ olt-mcp"

echo "--- Building olt-lsp ---"
odin build "$BUILD/src/lsp" \
    -out:"$OUT/olt-lsp" \
    -extra-linker-flags:"$LINKER_FLAGS"
echo "  ✓ olt-lsp"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅  Linux ARM64 build complete"
echo "   Binaries in: $OUT/"
ls -lh "$OUT/"
