#!/usr/bin/env bash
# run_graph_query_tests.sh — `olt symbol|callers|refs`, `--list-kinds` and `--db` help.
# Builds a throwaway two-package project so plain-name ambiguity is exercised for real.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

PROJ="$WORK/proj"
DB="$PROJ/.codegraph/g.db"
mkdir -p "$PROJ/alpha" "$PROJ/beta"

cat > "$PROJ/alpha/a.odin" <<'ODIN'
package alpha

foo :: proc(x: int) -> int { return x + 1 }

bar :: proc() -> int { return foo(1) }

Thing :: struct { value: int }

Color :: enum { red, green }

LIMIT :: 10

leaky :: proc() {
	xs := make([]u8, 10)
	xs[0] = 1
}
ODIN

cat > "$PROJ/beta/b.odin" <<'ODIN'
package beta

foo :: proc(x: int) -> int { return x * 2 }

use :: proc() -> int { return foo(2) }
ODIN

if "$OLT_BINARY" "$PROJ" --export-symbols --db "$DB" >"$WORK/export.log" 2>&1; then
  ok "export builds the code graph"
else
  bad "export builds the code graph"
  cat "$WORK/export.log"
  echo "graph query tests: $PASS passed, $FAIL failed"
  exit 1
fi

# ── --list-kinds and --help ─────────────────────────────────────────────────
"$OLT_BINARY" --list-kinds >"$WORK/kinds" 2>&1
check "--list-kinds names function"        'grep -q "^function	" "$WORK/kinds"'
check "--list-kinds names enum_member"     'grep -q "^enum_member	" "$WORK/kinds"'
check "--list-kinds has no proc kind"      '! grep -q "^proc" "$WORK/kinds"'

"$OLT_BINARY" --help >"$WORK/help" 2>&1
check "--help lists --db"                  'grep -q -- "--db <path>" "$WORK/help"'
check "--help lists olt symbol"            'grep -q "olt symbol <name>" "$WORK/help"'

# ── symbol ─────────────────────────────────────────────────────────────────
out="$("$OLT_BINARY" symbol alpha::foo --db "$DB" --json 2>"$WORK/err")"; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["name"] == "foo", d
assert d["kind"] == "function", d
assert d["file"].endswith("/alpha/a.odin"), d
assert d["line"] == 3, d
assert d["signature"].startswith("foo :: proc"), d
assert isinstance(d["lint_violations"], list), d
' 2>"$WORK/pyerr"; then
  ok "symbol --json returns the MCP symbol payload"
else
  bad "symbol --json returns the MCP symbol payload"
  cat "$WORK/err" "$WORK/pyerr" 2>/dev/null | head -5
fi

out="$("$OLT_BINARY" symbol alpha::leaky --db "$DB" --json 2>/dev/null)"
check "symbol --json exposes lint_violations" 'echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert \"C001\" in d[\"lint_violations\"], d"'

out="$("$OLT_BINARY" symbol bar --db "$DB" 2>/dev/null)"
check "symbol text output has kind and location" 'echo "$out" | grep -q "function" && echo "$out" | grep -q "a.odin:5"'

out="$("$OLT_BINARY" symbol foo --db "$DB" 2>"$WORK/err")"; rc=$?
check "ambiguous plain name exits 2"       '[ "$rc" -eq 2 ]'
check "ambiguity lists both packages"      'grep -q "alpha::foo" "$WORK/err" && grep -q "beta::foo" "$WORK/err"'

"$OLT_BINARY" symbol nope --db "$DB" >/dev/null 2>"$WORK/err"; rc=$?
check "missing symbol exits 1"             '[ "$rc" -eq 1 ]'

# ── callers / refs ─────────────────────────────────────────────────────────
out="$("$OLT_BINARY" callers alpha::foo --db="$DB" --json 2>/dev/null)"
check "callers --json returns the caller" 'echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"proc\"]==\"foo\", d; assert d[\"caller_count\"]==1, d; assert d[\"callers\"][0][\"name\"]==\"bar\", d"'

out="$("$OLT_BINARY" refs alpha::foo --db "$DB" --json 2>/dev/null)"
check "refs --json returns the call site" 'echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"reference_count\"]==1, d; r=d[\"references\"][0]; assert r[\"caller\"]==\"bar\" and r[\"kind\"]==\"calls\", d"'

# ── usage and database errors ──────────────────────────────────────────────
"$OLT_BINARY" symbol --db "$DB" >/dev/null 2>&1; rc=$?
check "missing name exits 2"               '[ "$rc" -eq 2 ]'

"$OLT_BINARY" symbol foo --bogus >/dev/null 2>&1; rc=$?
check "unknown flag exits 2"               '[ "$rc" -eq 2 ]'

"$OLT_BINARY" symbol foo --db >/dev/null 2>&1; rc=$?
check "--db without a path exits 2"        '[ "$rc" -eq 2 ]'

"$OLT_BINARY" symbol foo --db "$WORK/none.db" >/dev/null 2>"$WORK/err"; rc=$?
check "missing database exits 2"           '[ "$rc" -eq 2 ] && grep -q "graph db not found" "$WORK/err"'

echo "graph query tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
