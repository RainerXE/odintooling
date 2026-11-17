#!/usr/bin/env bash
# run_install_tests.sh — `olt --install` into a throwaway HOME.
# Regression: the binary must be installed on a fresh inode, never copied over a
# signed macOS binary in place (that makes the kernel kill every later run with
# "Code Signature Invalid").
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export HOME="$WORK/home"
mkdir -p "$HOME"
BIN="$HOME/.local/bin/olt"

install_once() {
  printf 'y\ny\ny\ny\ny\n' | "$OLT_BINARY" --install >>"$WORK/log" 2>&1
}

if install_once; then
  ok "--install exits 0"
else
  bad "--install exits 0"
  tail -20 "$WORK/log"
  echo "install tests: $PASS passed, $FAIL failed"
  exit 1
fi

check "installs ~/.local/bin/olt" '[ -x "$BIN" ]'
check "install writes no temporary sibling" '! ls -a "$HOME/.local/bin" | grep -q "^\.olt\.new"'
check "installed binary runs"    '"$BIN" --version >/dev/null 2>&1'
check "olt-lsp is a symlink to olt"  '[ -L "$HOME/.local/bin/olt-lsp" ] && [ "$(readlink "$HOME/.local/bin/olt-lsp")" = "$BIN" ]'
check "olt-mcp is a symlink to olt"  '[ -L "$HOME/.local/bin/olt-mcp" ] && [ "$(readlink "$HOME/.local/bin/olt-mcp")" = "$BIN" ]'

inode_before="$(ls -i "$BIN" | awk '{print $1}')"
if install_once; then
  ok "reinstall exits 0"
else
  bad "reinstall exits 0"
  tail -20 "$WORK/log"
fi
inode_after="$(ls -i "$BIN" | awk '{print $1}')"

check "reinstall replaces the inode" '[ -n "$inode_before" ] && [ -n "$inode_after" ] && [ "$inode_before" != "$inode_after" ]'
check "upgraded binary runs"     '"$BIN" --version >/dev/null 2>&1'

echo "install tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
