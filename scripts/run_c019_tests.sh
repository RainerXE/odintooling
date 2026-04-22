#!/bin/bash

# C019 Test Runner — type marker suffix conventions (opt-in)
# NOTE: C019 requires --rule C019 since it is opt-in (default: disabled).

echo "🧪 Running C019 Test Suite..."
echo "============================"

mkdir -p test_results/c019_results

PASS_COUNT=0
FAIL_COUNT=0

check_pass() {
    local label="$1"
    local out="$2"
    count=$(grep "C019 \[" "$out" 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + 0))
    if [ "$count" -eq 0 ]; then
        echo "✅ PASS: $label — no C019 violations (expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ FAIL: $label — unexpected C019 violations ($count found)"
        grep "C019 \[" "$out" | head -10
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_fail() {
    local label="$1"
    local out="$2"
    local expected="${3:-1}"
    count=$(grep "C019 \[" "$out" 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + 0))
    if [ "$count" -ge "$expected" ]; then
        echo "✅ PASS: $label — $count C019 violation(s) detected (expected ≥ $expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ FAIL: $label — expected ≥ $expected C019 violation(s), got $count"
        cat "$out"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "── Pass fixtures (0 violations expected) ──"

./artifacts/odin-lint --rule C019 tests/C019_STY_TYPEMARKER/c019_pass.odin \
    > test_results/c019_results/c019_pass_results.txt 2>&1
check_pass "c019_pass.odin" test_results/c019_results/c019_pass_results.txt

./artifacts/odin-lint --rule C019 tests/C019_STY_TYPEMARKER/c019_edge.odin \
    > test_results/c019_results/c019_edge_results.txt 2>&1
check_pass "c019_edge.odin" test_results/c019_results/c019_edge_results.txt

echo ""
echo "── Fail fixtures (violations expected) ──"

./artifacts/odin-lint --rule C019 tests/C019_STY_TYPEMARKER/c019_fail.odin \
    > test_results/c019_results/c019_fail_results.txt 2>&1
check_fail "c019_fail.odin" test_results/c019_results/c019_fail_results.txt 7

echo ""
echo "── Default behaviour: C019 off without --rule flag ──"
./artifacts/odin-lint tests/C019_STY_TYPEMARKER/c019_fail.odin \
    > test_results/c019_results/c019_default_off_results.txt 2>&1
count=$(grep "C019 \[" test_results/c019_results/c019_default_off_results.txt 2>/dev/null | wc -l | tr -d ' ')
count=$((count + 0))
if [ "$count" -eq 0 ]; then
    echo "✅ PASS: C019 is off by default (no violations without --rule C019)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "❌ FAIL: C019 fired without opt-in ($count violations)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "============================"
echo "C019 Test Suite Summary"
echo "============================"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "🎉 All C019 tests passed!"
    exit 0
else
    echo "❌ Some tests failed. Check test_results/c019_results/ for details."
    exit 1
fi
