#!/bin/bash

# C017 Test Runner — package-level variable camelCase naming

echo "Running C017 Test Suite..."
echo "=========================="
mkdir -p test_results/c017_results

test_files=(
    "tests/C017_STY_GLOBALNAME/c017_fixture_pass.odin"
    "tests/C017_STY_GLOBALNAME/c017_fixture_fail.odin"
)

total_tests=${#test_files[@]}
passed_tests=0
failed_tests=0

for test_file in "${test_files[@]}"; do
    echo "Testing: $(basename $test_file)"
    test_name=$(basename "$test_file" .odin)
    output_file="test_results/c017_results/${test_name}_results.txt"
    ./artifacts/odin-lint "$test_file" > "$output_file" 2>&1

    if [[ "$test_file" == *"pass"* ]]; then
        if ! grep -q "C017" "$output_file"; then
            echo "  PASS: No C017 violations (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: Unexpected C017 violation"
            cat "$output_file"
            ((failed_tests++))
        fi
    elif [[ "$test_file" == *"fail"* ]]; then
        if grep -q "C017" "$output_file"; then
            count=$(grep -c "C017" "$output_file")
            echo "  PASS: $count C017 violation(s) detected (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: No C017 violations found (expected some)"
            ((failed_tests++))
        fi
    fi
done

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C017 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
