#!/usr/bin/env bash
# _build_linux_inner.sh — shared Linux build + smoke-test logic.
# Run directly on Linux, or via a Podman wrapper script.
#
# Usage:
#   bash _build_linux_inner.sh            # native Linux (auto-detects arch)
#   bash _build_linux_inner.sh podman     # called by podman wrapper (appends -podman suffix)
#
# Expects to be run from the repo root (or with BUILD set to the repo root).

set -euo pipefail

BUILD="${BUILD:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SUFFIX="${1:-}"     # "podman" when called from a Podman wrapper
LIBS="/tmp/olt-libs-$$"
mkdir -p "$LIBS"

# ── Detect architecture ────────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  arm64|aarch64) ARCH_LABEL="arm64";  ODIN_ARCH="arm64"  ;;
  x86_64|amd64)  ARCH_LABEL="x86_64"; ODIN_ARCH="amd64"  ;;
  *) echo "Unsupported architecture: $ARCH"; exit 2 ;;
esac

PLATFORM="linux-${ARCH_LABEL}${SUFFIX:+-$SUFFIX}"
OUT="$BUILD/artifacts/$PLATFORM"
mkdir -p "$OUT"

echo "============================================="
echo "  olt Linux build"
echo "  Architecture: $ARCH_LABEL"
echo "  Platform tag: $PLATFORM"
echo "  Output:       $OUT/"
echo "============================================="

# ── 1. System dependencies (Ubuntu/Debian) ────────────────────────────────────
if command -v apt-get &>/dev/null; then
  echo ""
  echo "--- Installing build dependencies ---"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      gcc clang make wget curl git xz-utils unzip ca-certificates
fi

# ── 2. libtree-sitter.a ───────────────────────────────────────────────────────
echo ""
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
ar rcs "$LIBS/libtree-sitter-odin.a" \
    "$LIBS/ts-odin-parser.o" "$LIBS/ts-odin-scanner.o"
echo "  ✓ libtree-sitter-odin.a"

# ── 4. libsqlite3.a ───────────────────────────────────────────────────────────
echo "--- Building libsqlite3 ---"
SQLITE_VER="3460100"
SQLITE_DIR="sqlite-amalgamation-${SQLITE_VER}"
wget -q "https://sqlite.org/2024/${SQLITE_DIR}.zip" -O /tmp/sqlite-$$.zip
unzip -q /tmp/sqlite-$$.zip -d /tmp/sqlite-$$
gcc -O2 -fPIC \
    -DSQLITE_THREADSAFE=0 \
    -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
    -c "/tmp/sqlite-$$/${SQLITE_DIR}/sqlite3.c" \
    -o "$LIBS/sqlite3.o"
ar rcs "$LIBS/libsqlite3.a" "$LIBS/sqlite3.o"
rm -rf /tmp/sqlite-$$.zip "/tmp/sqlite-$$"
echo "  ✓ libsqlite3.a"

# ── 5. Install Odin ───────────────────────────────────────────────────────────
echo "--- Installing Odin ---"
ODIN_TAG="dev-2026-04"
ODIN_URL="https://github.com/odin-lang/Odin/releases/download/${ODIN_TAG}/odin-linux-${ODIN_ARCH}-${ODIN_TAG}.tar.gz"
wget -q "$ODIN_URL" -O /tmp/odin-$$.tar.gz
mkdir -p /opt/odin
tar xzf /tmp/odin-$$.tar.gz -C /opt/odin --strip-components=1
rm -f /tmp/odin-$$.tar.gz
export PATH="/opt/odin:$PATH"
odin version
echo "  ✓ Odin installed"

# ── 6. Build binaries ─────────────────────────────────────────────────────────
LINKER_FLAGS="$LIBS/libtree-sitter.a $LIBS/libtree-sitter-odin.a $LIBS/libsqlite3.a"

echo ""
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

# ── 7. Smoke tests ────────────────────────────────────────────────────────────
echo ""
echo "--- Smoke tests ---"
PASS=0; FAIL=0

smoke_check() {
  local label="$1"; local condition="$2"
  if [ "$condition" = "ok" ]; then
    echo "  ✓ $label"
    PASS=$((PASS+1))
  else
    echo "  ✗ $label  ← FAILED"
    FAIL=$((FAIL+1))
  fi
}

OLT="$OUT/olt"

# --version: must exit 0 and contain "olt"
ver_out=$("$OLT" --version 2>&1) && ver_ok=$? || ver_ok=$?
smoke_check "--version exits 0"            "$([ $ver_ok  -eq 0 ] && echo ok || echo fail)"
smoke_check "--version contains 'olt'"    "$(echo "$ver_out" | grep -q 'olt' && echo ok || echo fail)"

# --list-rules: must exit 0 and list C001
rules_out=$("$OLT" --list-rules 2>&1) && rules_ok=$? || rules_ok=$?
smoke_check "--list-rules exits 0"        "$([ $rules_ok -eq 0 ] && echo ok || echo fail)"
smoke_check "--list-rules contains C001"  "$(echo "$rules_out" | grep -q 'C001' && echo ok || echo fail)"

# Lint a clean file: must exit 0
cat > /tmp/smoke_clean.odin <<'ODIN'
package smoke
clean :: proc() { _ = 1 + 1 }
ODIN
clean_ok=0
"$OLT" /tmp/smoke_clean.odin >/dev/null 2>&1 || clean_ok=$?
smoke_check "lint clean file exits 0"     "$([ $clean_ok -eq 0 ] && echo ok || echo fail)"

# Lint a file with a known violation (C001 leak): must exit 1
cat > /tmp/smoke_leak.odin <<'ODIN'
package smoke_leak
leak :: proc() { _ = make([]u8, 10) }
ODIN
leak_ok=0
"$OLT" /tmp/smoke_leak.odin >/dev/null 2>&1 || leak_ok=$?
smoke_check "lint leaky file exits 1"     "$([ $leak_ok -eq 1 ] && echo ok || echo fail)"

# olt-mcp: starts cleanly and exits on EOF
mcp_ok=0
echo "" | timeout 3 "$OUT/olt-mcp" >/dev/null 2>&1 || mcp_ok=$?
# timeout returns 124 on timeout, binary error on crash (non 0/1/124)
smoke_check "olt-mcp starts (no crash)"   "$([ $mcp_ok -ne 139 ] && [ $mcp_ok -ne 134 ] && echo ok || echo fail)"

# olt-lsp: starts cleanly and exits on EOF
lsp_ok=0
echo "" | timeout 3 "$OUT/olt-lsp" >/dev/null 2>&1 || lsp_ok=$?
smoke_check "olt-lsp starts (no crash)"   "$([ $lsp_ok -ne 139 ] && [ $lsp_ok -ne 134 ] && echo ok || echo fail)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  Build complete: $PLATFORM"
ls -lh "$OUT/"
echo ""
echo "  Smoke tests: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
  echo "❌  $FAIL smoke test(s) failed — binaries may be broken"
  exit 1
fi
echo "✅  All smoke tests passed"
