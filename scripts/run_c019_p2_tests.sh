#!/usr/bin/env bash
# run_c019_p2_tests.sh — C019 Phase 2 (graph-backed inferred type markers)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/odin-lint"
FAIL_FIXTURE="$REPO_ROOT/tests/C019_P2_TYPE_MARKER/c019_p2_fixture_fail.odin"
PASS_FIXTURE="$REPO_ROOT/tests/C019_P2_TYPE_MARKER/c019_p2_fixture_pass.odin"
TEST_DB="$REPO_ROOT/test_results/c019_p2_results/c019_p2_test.db"

PASS=0; FAIL=0

check() {
    local label="$1" condition="$2" detail="${3:-}"
    if [ "$condition" = "true" ]; then
        echo "  ✅ PASS: $label"; PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $label${detail:+ — $detail}"; FAIL=$((FAIL + 1))
    fi
}

echo "🧪 C019 Phase 2 (graph-backed inferred types) Test Suite"
echo "========================================================="

mkdir -p "$(dirname "$TEST_DB")"
rm -f "$TEST_DB"

echo ""
echo "── Building test graph DB from fixtures ──"
"$BINARY" "$REPO_ROOT/tests/C019_P2_TYPE_MARKER/" --export-symbols --db "$TEST_DB" 2>&1 || true

# ── Fail fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Fail fixture (--rule C019 enables explicitly, --db provides Phase 2 graph) ──"

output=$("$BINARY" "$FAIL_FIXTURE" --rule C019 --db "$TEST_DB" 2>&1 || true)
count=$(echo "$output" | grep -c " C019 \[" || true)
check "fail fixture produces C019 Phase 2 violations"  "$([ "$count" -gt 0 ] && echo true || echo false)" "got $count"
check "get_player (^int → _ptr) detected"              "$(echo "$output" | grep -q "player"  && echo true || echo false)"
check "get_items ([]int → _slice) detected"            "$(echo "$output" | grep -q "items"   && echo true || echo false)"
check "get_lookup (map → _map) detected"               "$(echo "$output" | grep -q "lookup"  && echo true || echo false)"
check "get_label (cstring → _cstr) detected"           "$(echo "$output" | grep -q "label"   && echo true || echo false)"

# ── Pass fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass fixture ──"
pass_output=$("$BINARY" "$PASS_FIXTURE" --rule C019 --db "$TEST_DB" 2>&1 || true)
pass_count=$(echo "$pass_output" | grep -c " C019 \[" || true)
check "pass fixture has 0 C019 violations"             "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

# ── Phase 1 unaffected: no graph DB → Phase 1 only, no crash ──────────────────
echo ""
echo "── Phase 1 unaffected (no DB) ──"
p1_output=$("$BINARY" "$FAIL_FIXTURE" --rule C019 2>&1 || true)
p1_p2=$(echo "$p1_output" | grep -c " C019 \[" || true)
check "without graph DB: only Phase 1 fires (no Phase 2 FP)" \
    "$([ "$p1_p2" -eq 0 ] && echo true || echo false)" \
    "got $p1_p2 (all are inferred calls — Phase 1 can't detect them)"

# ── Own codebase regression ───────────────────────────────────────────────────
echo ""
echo "── Own codebase regression (no --rule C019; opt-in gate blocks it) ──"
own_output=$("$BINARY" "$REPO_ROOT/src" 2>&1 || true)
own_count=$(echo "$own_output" | grep -c " C019 \[" || true)
check "own codebase 0 C019 violations (opt-in gate active)"  "$([ "$own_count" -eq 0 ] && echo true || echo false)" "got $own_count"

echo ""
echo "========================================================="
echo "C019 Phase 2 Test Summary"
echo "========================================================="
echo "Passed: $PASS  Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then echo "🎉 All C019 Phase 2 tests passed!"; exit 0
else echo "❌ $FAIL test(s) failed."; exit 1; fi
