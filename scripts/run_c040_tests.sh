#!/usr/bin/env bash
# run_c040_tests.sh — C040: manual free of temp/arena memory (graph-backed).
#
# Builds a graph for the fixtures, then checks the rule, the analyzer's allocator
# classification, the symbol payload and the JSON aliases the lint channel consumes.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_platform.sh"
BINARY="$OLT_BINARY"

FIXTURE_DIR="$REPO_ROOT/tests/C040_COR_ARENA_FREE"
FAIL_FIXTURE="$FIXTURE_DIR/c040_fixture_fail.odin"
PASS_FIXTURE="$FIXTURE_DIR/c040_fixture_pass.odin"
TEST_DB="$REPO_ROOT/test_results/c040_results/c040_test.db"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
check() {
	local label="$1" condition="$2" detail="${3:-}"
	if [ "$condition" = "true" ]; then
		echo "  ✅ PASS: $label"; PASS=$((PASS + 1))
	else
		echo "  ❌ FAIL: $label${detail:+ — $detail}"; FAIL=$((FAIL + 1))
	fi
}

dbq() {
	python3 - "$TEST_DB" "$1" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
row = con.execute(sys.argv[2]).fetchone()
print("" if row is None or row[0] is None else row[0])
PY
}

echo "🧪 C040 Temp/Arena Free Test Suite"
echo "=================================="

mkdir -p "$(dirname "$TEST_DB")"
rm -f "$TEST_DB" "$TEST_DB-wal" "$TEST_DB-shm"

echo ""
echo "── Building test graph DB from fixtures ──"
"$BINARY" "$FIXTURE_DIR/" --export-symbols --db "$TEST_DB" >/dev/null 2>&1

# ── Fail fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Fail fixture ──"
out=$("$BINARY" "$FAIL_FIXTURE" --rule C040 --db "$TEST_DB" 2>&1 || true)
count=$(printf '%s\n' "$out" | grep -c "C040" || true)
check "fail fixture produces six C040 findings" "$([ "$count" -eq 6 ] && echo true || echo false)" "got $count"
check "temp slice reported"          "$(echo "$out" | grep -q "manual free of 'buf'" && echo true || echo false)"
check "temp dynamic array reported"  "$(echo "$out" | grep -q "manual free of 'args'" && echo true || echo false)"
check "two-argument temp dynamic reported" "$(echo "$out" | grep -q "manual free of 'xs'.*temp_allocator" && echo true || echo false)"
check "temp new + free reported"     "$(echo "$out" | grep -q "manual free of 'p'.*temp_allocator" && echo true || echo false)"
check "explicit arena reported"      "$(echo "$out" | grep -q "arena_allocator(&arena)" && echo true || echo false)"
check "arena alias reported"         "$(echo "$out" | grep -q "arena (a)" && echo true || echo false)"

# ── Pass fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass fixture ──"
pass_out=$("$BINARY" "$PASS_FIXTURE" --rule C040 --db "$TEST_DB" 2>&1 || true)
pass_count=$(printf '%s\n' "$pass_out" | grep -c "C040" || true)
check "pass fixture has 0 C040 violations" "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

suppressed_sites=$(dbq "SELECT COUNT(*) FROM odin_alloc_site a JOIN nodes p ON p.id=a.proc_id WHERE p.name='suppressed_temp' AND a.allocator_kind='temp'")
check "the suppressed temp site exists in the graph" "$([ "$suppressed_sites" = "1" ] && echo true || echo false)" "got $suppressed_sites"

# ── Analyzer classification: a length constant is not an allocator ────────────
echo ""
echo "── Analyzer classification ──"
size_sites=$(dbq "SELECT COUNT(*) FROM odin_alloc_site a JOIN nodes p ON p.id=a.proc_id WHERE p.name='arena_explicit' AND a.api='make' AND COALESCE(a.allocator_expr,'')='ARENA_SIZE'")
check "ARENA_SIZE length is not recorded as an allocator" "$([ "$size_sites" = "0" ] && echo true || echo false)" "got $size_sites"

backing_kind=$(dbq "SELECT a.allocator_kind FROM odin_alloc_site a JOIN nodes p ON p.id=a.proc_id WHERE p.name='arena_explicit' AND a.api='make' ORDER BY a.line LIMIT 1")
check "the arena backing buffer is a default allocation" "$([ "$backing_kind" = "default" ] && echo true || echo false)" "got $backing_kind"

dynamic_kind=$(dbq "SELECT a.allocator_kind FROM odin_alloc_site a JOIN nodes p ON p.id=a.proc_id WHERE p.name='dynamic_default' AND a.api='make'")
check "a dynamic capacity is not an allocator" "$([ "$dynamic_kind" = "default" ] && echo true || echo false)" "got $dynamic_kind"

map_kind=$(dbq "SELECT a.allocator_kind FROM odin_alloc_site a JOIN nodes p ON p.id=a.proc_id WHERE p.name='map_default' AND a.api='make'")
check "a map capacity is not an allocator" "$([ "$map_kind" = "default" ] && echo true || echo false)" "got $map_kind"

# ── Symbol payload ────────────────────────────────────────────────────────────
echo ""
echo "── Graph payload ──"
symbol_out=$("$BINARY" symbol temp_slice --db "$TEST_DB" --json 2>/dev/null || true)
symbol_ok=$(echo "$symbol_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("true" if "C040" in d["lint_violations"] else "false")' 2>/dev/null || echo false)
check "symbol --json carries C040 in lint_violations" "$symbol_ok"

# ── JSON aliases the lint channel consumes ───────────────────────────────────
echo ""
echo "── JSON output ──"
json_out=$("$BINARY" "$FAIL_FIXTURE" --rule C040 --db "$TEST_DB" --format json 2>/dev/null || true)
json_ok=$(echo "$json_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)[0]
print("true" if d.get("code")=="C040" and d.get("severity") in ("error","warning","note") and d.get("col")==d.get("column") and d.get("symbol")=="temp_slice" else "false")' 2>/dev/null || echo false)
check "JSON has code, severity, col and symbol" "$json_ok"

# ── Exact-shape lint channel ──────────────────────────────────────────────────
echo ""
echo "── Lint channel ──"
lint_out=$("$BINARY" "$FAIL_FIXTURE" --rule C040 --db "$TEST_DB" --format lint 2>/dev/null || true)
lint_keys=$(echo "$lint_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("true" if len(d)==6 and all(set(x)=={"file","line","col","severity","code","message","symbol"} for x in d) else "false")' 2>/dev/null || echo false)
check "lint format emits the exact seven keys for all findings" "$lint_keys"
lint_symbol=$(echo "$lint_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("true" if all(x["symbol"] for x in d) and d[0]["symbol"]=="temp_slice" else "false")' 2>/dev/null || echo false)
check "lint format carries the enclosing procedure symbol" "$lint_symbol"
lint_clean=$("$BINARY" "$PASS_FIXTURE" --rule C040 --db "$TEST_DB" --format lint 2>/dev/null || true)
check "lint format emits [] on a clean file" "$([ "$lint_clean" = "[]" ] && echo true || echo false)" "got $lint_clean"
pkg_out=$("$BINARY" "$REPO_ROOT/tests/B002_STR_PACKAGENAME/wrong_pkg" --rule B002 --format lint 2>/dev/null || true)
pkg_symbol=$(echo "$pkg_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("true" if d and all(x["symbol"]=="" for x in d) else "false")' 2>/dev/null || echo false)
check "lint symbol is empty for file-scope findings" "$pkg_symbol"

# ── No graph DB ───────────────────────────────────────────────────────────────
echo ""
echo "── Without a graph ──"
no_db=$("$BINARY" "$FAIL_FIXTURE" --rule C040 --db "$WORK/none.db" 2>&1 || true)
check "silent without a graph DB" "$(echo "$no_db" | grep -q "C040" && echo false || echo true)"

# ── Discovery ─────────────────────────────────────────────────────────────────
echo ""
echo "── Discovery ──"
"$BINARY" --list-rules >"$WORK/rules" 2>&1
check "--list-rules names C040" "$(grep -q '^C040' "$WORK/rules" && echo true || echo false)"
"$BINARY" --explain C040 >"$WORK/explain" 2>&1
check "--explain C040 documents the rule" "$(grep -q 'Manual free of temp/arena memory' "$WORK/explain" && echo true || echo false)"

echo ""
echo "=================================="
echo "C040 Test Summary"
echo "=================================="
echo "Passed: $PASS  Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then echo "🎉 All C040 tests passed!"; exit 0
else echo "❌ $FAIL test(s) failed."; exit 1; fi
