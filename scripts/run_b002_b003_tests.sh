#!/bin/bash
# B002 / B003 Test Runner — package name consistency + subfolder clash

echo "Running B002/B003 Test Suite..."
echo "================================"
mkdir -p test_results/b002_b003_results

passed=0
failed=0

run_pass() {
    local dir=$1 label=$2
    local out="test_results/b002_b003_results/${label}_results.txt"
    ./artifacts/odin-lint "$dir" > "$out" 2>&1
    if ! grep -qE "\bB002\b|\bB003\b" "$out"; then
        echo "  PASS: No B002/B003 violations (as expected) — $label"
        ((passed++))
    else
        echo "  FAIL: Unexpected B002/B003 violation — $label"
        grep -E "\bB002\b|\bB003\b" "$out"
        ((failed++))
    fi
}

run_fail() {
    local dir=$1 label=$2 expected_rule=$3
    local out="test_results/b002_b003_results/${label}_results.txt"
    ./artifacts/odin-lint "$dir" > "$out" 2>&1
    if grep -qE "\b${expected_rule}\b" "$out"; then
        local count=$(grep -cE "\b${expected_rule}\b" "$out")
        echo "  PASS: $count $expected_rule violation(s) detected — $label"
        ((passed++))
    else
        echo "  FAIL: No $expected_rule violations found (expected some) — $label"
        cat "$out"
        ((failed++))
    fi
}

echo ""
echo "--- B002: Package Name Consistency ---"
run_pass "tests/B002_STR_PACKAGENAME/correct_pkg/" "b002_correct"
run_fail "tests/B002_STR_PACKAGENAME/wrong_pkg/"   "b002_wrong"   "B002"

echo ""
echo "--- B003: Subfolder Shares Parent Package Name ---"
run_fail "tests/B003_STR_SUBFOLDERPACKAGE/parent/" "b003_clash"   "B003"

echo ""
echo "================================"
total=$((passed + failed))
echo "Total: $total  Passed: $passed  Failed: $failed"
if [ $failed -eq 0 ]; then
    echo "All B002/B003 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
