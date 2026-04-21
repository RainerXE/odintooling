#!/bin/bash

# B001 Test Runner — unmatched brace / unclosed block

echo "Running B001 Test Suite..."
echo "=========================="
mkdir -p test_results/b001_results

passed_tests=0
failed_tests=0

run_pass() {
    local file=$1
    local name=$(basename "$file" .odin)
    local out="test_results/b001_results/${name}_results.txt"
    ./artifacts/odin-lint "$file" > "$out" 2>&1
    if ! grep -q "B001 \[structural\]" "$out"; then
        echo "  PASS: No B001 violations (as expected)"
        ((passed_tests++))
    else
        echo "  FAIL: Unexpected B001 violation"
        grep "B001" "$out"
        ((failed_tests++))
    fi
}

run_fail() {
    local file=$1
    local name=$(basename "$file" .odin)
    local out="test_results/b001_results/${name}_results.txt"
    ./artifacts/odin-lint "$file" > "$out" 2>&1
    if grep -q "B001 \[structural\]" "$out"; then
        local count=$(grep -c "B001 \[structural\]" "$out")
        echo "  PASS: $count B001 violation(s) detected (as expected)"
        ((passed_tests++))
    else
        echo "  FAIL: No B001 violations found (expected some)"
        cat "$out"
        ((failed_tests++))
    fi
}

echo "Testing: b001_fixture_pass.odin"
run_pass "tests/B001_STR_BRACEBALANCE/b001_fixture_pass.odin"

echo "Testing: b001_fixture_unclosed.odin"
run_fail "tests/B001_STR_BRACEBALANCE/b001_fixture_unclosed.odin"

echo "Testing: b001_fixture_surplus.odin"
run_fail "tests/B001_STR_BRACEBALANCE/b001_fixture_surplus.odin"

echo ""
echo "=========================="
total=$((passed_tests + failed_tests))
echo "Total: $total  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All B001 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
