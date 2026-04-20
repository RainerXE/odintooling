#!/bin/bash

# C018 Test Runner — proc visibility naming (private=snake_case, public=PascalCase)
#
# NOTE: C018 conflicts with C003 by design. When C018 is enabled, C003 should
# be disabled. Tests check for C018 specifically, not zero total violations.

echo "Running C018 Test Suite..."
echo "=========================="
mkdir -p test_results/c018_results

test_files=(
    "tests/C018_STY_PROCVISIBILITY/c018_fixture_pass.odin"
    "tests/C018_STY_PROCVISIBILITY/c018_fixture_fail.odin"
)

total_tests=${#test_files[@]}
passed_tests=0
failed_tests=0

for test_file in "${test_files[@]}"; do
    echo "Testing: $(basename $test_file)"
    test_name=$(basename "$test_file" .odin)
    output_file="test_results/c018_results/${test_name}_results.txt"
    # C018 is opt-in; use --rule=C018 to force-enable it for testing
    ./artifacts/odin-lint --rule=C018 "$test_file" > "$output_file" 2>&1

    if [[ "$test_file" == *"pass"* ]]; then
        # Pass fixture: must produce zero C018 violations (C003 may still fire)
        if ! grep -q "C018 \[style\]" "$output_file"; then
            echo "  PASS: No C018 violations (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: Unexpected C018 violation"
            grep "C018" "$output_file"
            ((failed_tests++))
        fi
    elif [[ "$test_file" == *"fail"* ]]; then
        if grep -q "C018 \[style\]" "$output_file"; then
            count=$(grep -c "C018 \[style\]" "$output_file")
            echo "  PASS: $count C018 violation(s) detected (as expected)"
            ((passed_tests++))
        else
            echo "  FAIL: No C018 violations found (expected some)"
            ((failed_tests++))
        fi
    fi
done

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C018 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
