#!/bin/bash

# C020 Test Runner — short variable/parameter names (opt-in)
#
# C020 flags names shorter than c020_min_length that are not on the allowlist.
# Use --rule=C020 to force-enable it for testing.

echo "Running C020 Test Suite..."
echo "=========================="
mkdir -p test_results/c020_results

test_files=(
    "tests/C020_STY_SHORTNAME/c020_fixture_pass.odin"
    "tests/C020_STY_SHORTNAME/c020_fixture_fail.odin"
)

total_tests=${#test_files[@]}
passed_tests=0
failed_tests=0

for test_file in "${test_files[@]}"; do
    echo "Testing: $(basename $test_file)"
    test_name=$(basename "$test_file" .odin)
    output_file="test_results/c020_results/${test_name}_results.txt"
    ./artifacts/odin-lint --rule=C020 "$test_file" > "$output_file" 2>&1

    if [[ "$test_file" == *"pass"* ]]; then
        if ! grep -q "C020 \[style\]" "$output_file"; then
            echo "  PASS: No C020 violations (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: Unexpected C020 violation"
            grep "C020" "$output_file"
            ((failed_tests++))
        fi
    elif [[ "$test_file" == *"fail"* ]]; then
        if grep -q "C020 \[style\]" "$output_file"; then
            count=$(grep -c "C020 \[style\]" "$output_file")
            echo "  PASS: $count C020 violation(s) detected (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: No C020 violations found (expected some)"
            cat "$output_file"
            ((failed_tests++))
        fi
    fi
done

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C020 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
