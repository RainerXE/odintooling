#!/bin/bash

# C016 Test Runner — local variable snake_case naming

echo "Running C016 Test Suite..."
echo "=========================="
mkdir -p test_results/c016_results

test_files=(
    "tests/C016_STY_LOCALNAME/c016_fixture_pass.odin"
    "tests/C016_STY_LOCALNAME/c016_fixture_fail.odin"
)

total_tests=${#test_files[@]}
passed_tests=0
failed_tests=0

for test_file in "${test_files[@]}"; do
    echo "Testing: $(basename $test_file)"
    test_name=$(basename "$test_file" .odin)
    output_file="test_results/c016_results/${test_name}_results.txt"
    ./artifacts/odin-lint "$test_file" > "$output_file" 2>&1

    if [[ "$test_file" == *"pass"* ]]; then
        if ! grep -q "C016" "$output_file"; then
            echo "  PASS: No C016 violations (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: Unexpected C016 violation"
            cat "$output_file"
            ((failed_tests++))
        fi
    elif [[ "$test_file" == *"fail"* ]]; then
        if grep -q "C016" "$output_file"; then
            count=$(grep -c "C016" "$output_file")
            echo "  PASS: $count C016 violation(s) detected (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: No C016 violations found (expected some)"
            ((failed_tests++))
        fi
    fi
done

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C016 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
