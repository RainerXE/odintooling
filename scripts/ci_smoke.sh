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

# The code graph must build with its full schema. A SQLite built without FTS5 creates the
# base tables and then fails on nodes_fts, leaving nothing usable (how the 0.97.x Linux
# builds lost the graph), so this checks the export, the node rows and the FTS index.
mkdir -p "$TMP/proj"
printf 'package p\n\nStatus :: enum { ok, busy }\n\nfiber_status :: proc(s: Status) -> int {\n\treturn int(s)\n}\n' > "$TMP/proj/sym.odin"
rc=0; "$OLT" "$TMP/proj" --export-symbols --db "$TMP/proj/.codegraph/g.db" >"$TMP/export.log" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "--export-symbols exits 0"
else
  fail "--export-symbols exits 0 (got $rc)"
  sed 's/^/       /' "$TMP/export.log"
fi

if python3 - "$TMP/proj/.codegraph/g.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
assert db.execute("select count(*) from nodes").fetchone()[0] > 0, "no nodes"
row = db.execute("select kind, start_line, end_line from nodes where name='fiber_status'").fetchone()
assert row and row[1] > 0 and row[2] >= row[1], "symbol row missing"
assert db.execute("select count(*) from nodes_fts where nodes_fts match 'fiber_status'").fetchone()[0] > 0, "FTS index empty"
PY
then
  ok "the graph has nodes and a working FTS5 index"
else
  fail "the graph has nodes and a working FTS5 index"
fi

rm -rf "$TMP"
exit "$FAILED"
