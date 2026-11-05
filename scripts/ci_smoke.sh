#!/usr/bin/env bash
# ci_smoke.sh <artifact-dir> — quick checks that a freshly built olt starts and lints.
# Used by .github/workflows/build.yml on macOS and Linux. Run from the repository root.
set -u

DIR="${1:?usage: ci_smoke.sh <artifact-dir>, e.g. artifacts/linux-x86_64}"
OLT="$DIR/olt"
TMP="$(mktemp -d)"
FAILED=0

ok()   { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILED=1; }

"$OLT" --version | grep -q 'olt'     && ok "--version names olt"     || fail "--version names olt"
"$OLT" --list-rules | grep -q 'C001' && ok "--list-rules lists C001" || fail "--list-rules lists C001"

printf 'package s\nclean :: proc() { _ = 1 + 1 }\n' > "$TMP/clean.odin"
printf 'package l\nleak :: proc() {\n\txs := make([]u8, 10)\n\txs[0] = 1\n}\n' > "$TMP/leak.odin"

rc=0; "$OLT" "$TMP/clean.odin" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "a clean file exits 0" || fail "a clean file exits 0 (got $rc)"

rc=0; "$OLT" "$TMP/leak.odin" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "a leaking file exits 1" || fail "a leaking file exits 1 (got $rc)"

# olt-mcp and olt-lsp start and leave on EOF without crashing (139 = segfault, 134 = abort).
# `timeout` is GNU coreutils; macOS runners have it as gtimeout or not at all, so fall back to a plain run.
TIMEOUT=""
command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 3"
command -v gtimeout >/dev/null 2>&1 && TIMEOUT="gtimeout 3"
for tool in olt-mcp olt-lsp; do
  rc=0
  echo "" | $TIMEOUT "$DIR/$tool" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 139 ] && [ "$rc" -ne 134 ]; then ok "$tool starts without crashing"; else fail "$tool starts without crashing (got $rc)"; fi
done

rm -rf "$TMP"
exit "$FAILED"
