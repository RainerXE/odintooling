#!/bin/bash

# C101 Test Runner — context.allocator assigned without defer restore

echo "🧪 Running C101 Test Suite..."
echo "============================"

mkdir -p test_results/c101_results

PASS_COUNT=0
FAIL_COUNT=0

check_pass() {
    local label="$1"
    local out="$2"
    count=$(grep "C101 \[" "$out" 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + 0))
    if [ "$count" -eq 0 ]; then
        echo "✅ PASS: $label — no C101 violations (expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ FAIL: $label — unexpected C101 violations ($count found)"
        grep "C101 \[" "$out" | head -5
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_fail() {
    local label="$1"
    local out="$2"
    local expected="${3:-1}"
    count=$(grep "C101 \[" "$out" 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + 0))
    if [ "$count" -ge "$expected" ]; then
        echo "✅ PASS: $label — $count C101 violation(s) detected (expected ≥ $expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ FAIL: $label — expected ≥ $expected C101 violation(s), got $count"
        cat "$out"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "── Pass fixtures (should produce 0 C101 violations) ──"

./artifacts/odin-lint tests/C101_CTX_INTEGRITY/c101_pass.odin \
    > test_results/c101_results/c101_pass_results.txt 2>&1
check_pass "c101_pass.odin" test_results/c101_results/c101_pass_results.txt

./artifacts/odin-lint tests/C101_CTX_INTEGRITY/c101_edge.odin \
    > test_results/c101_results/c101_edge_results.txt 2>&1
check_pass "c101_edge.odin" test_results/c101_results/c101_edge_results.txt

echo ""
echo "── Fail fixtures (should detect C101 violations) ──"

./artifacts/odin-lint tests/C101_CTX_INTEGRITY/c101_fail.odin \
    > test_results/c101_results/c101_fail_results.txt 2>&1
check_fail "c101_fail.odin" test_results/c101_results/c101_fail_results.txt 2

echo ""
echo "============================"
echo "C101 Test Suite Summary"
echo "============================"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "🎉 All C101 tests passed!"
    exit 0
else
    echo "❌ Some tests failed. Check test_results/c101_results/ for details."
    exit 1
fi
