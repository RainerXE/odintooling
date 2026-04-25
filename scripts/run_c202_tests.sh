#!/usr/bin/env bash
# run_c202_tests.sh — C202 switch exhaustiveness tests
# Requires graph DB with enum members: run from project root after --export-symbols

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/odin-lint"
FAIL_FIXTURE="$REPO_ROOT/tests/C202_COR_SWITCH_EXHAUST/c202_fixture_fail.odin"
PASS_FIXTURE="$REPO_ROOT/tests/C202_COR_SWITCH_EXHAUST/c202_fixture_pass.odin"
TEST_DB="$REPO_ROOT/test_results/c202_results/c202_test.db"

PASS=0; FAIL=0

check() {
    local label="$1" condition="$2" detail="${3:-}"
    if [ "$condition" = "true" ]; then
        echo "  ✅ PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $label${detail:+ — $detail}"
        FAIL=$((FAIL + 1))
    fi
}

echo "🧪 C202 Switch Exhaustiveness Test Suite"
echo "=========================================="

# Build a temporary graph DB from the test fixtures
mkdir -p "$(dirname "$TEST_DB")"
rm -f "$TEST_DB"

echo ""
echo "── Building test graph DB from fixtures ──"
"$BINARY" "$REPO_ROOT/tests/C202_COR_SWITCH_EXHAUST/" --export-symbols --db "$TEST_DB" 2>&1 || true

# ── Fail fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Fail fixture ──"
output=$("$BINARY" "$FAIL_FIXTURE" --rule C202 --db "$TEST_DB" 2>&1 || true)
count=$(echo "$output" | grep -c "C202" || true)
check "fail fixture produces C202 violations"     "$([ "$count" -gt 0 ] && echo true || echo false)" "got $count"
check "missing .Blue detected"                    "$(echo "$output" | grep -q "Blue"   && echo true || echo false)"
check "missing .Running/.Done/.Failed detected"   "$(echo "$output" | grep -q "Running\|Done\|Failed" && echo true || echo false)"

# ── Pass fixture ──────────────────────────────────────────────────────────────
echo ""
echo "── Pass fixture ──"
pass_output=$("$BINARY" "$PASS_FIXTURE" --rule C202 --db "$TEST_DB" 2>&1 || true)
pass_count=$(echo "$pass_output" | grep -c "C202" || true)
check "pass fixture has 0 C202 violations"        "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

# ── Own codebase regression ───────────────────────────────────────────────────
echo ""
echo "── Own codebase regression ──"
own_output=$("$BINARY" "$REPO_ROOT/src" --rule C202 2>&1 || true)
own_count=$(echo "$own_output" | grep -c "C202" || true)
check "own codebase produces 0 C202 violations"   "$([ "$own_count" -eq 0 ] && echo true || echo false)" "got $own_count"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "C202 Test Summary"
echo "=========================================="
echo "Passed: $PASS  Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then echo "🎉 All C202 tests passed!"; exit 0
else echo "❌ $FAIL test(s) failed."; exit 1; fi
