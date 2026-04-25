#!/bin/bash

# C015 Test Runner — private constants/variables never referenced (dead code, opt-in)
#
# C015 is a graph-query rule: requires --export-symbols to build the call graph,
# then does a word-boundary text scan to find unreferenced private symbols.
# Enabled via [domains] dead_code = true in olt.toml.

echo "Running C015 Test Suite..."
echo "=========================="
mkdir -p test_results/c015_results

FIXTURE_DIR="tests/C015_DEA_UNUSEDCONST"
TOML="$FIXTURE_DIR/olt.toml"

cat > "$TOML" <<'EOF'
[domains]
dead_code = true
EOF

total_tests=2
passed_tests=0
failed_tests=0

# --- Pass fixture ---
echo "Testing: c015_fixture_pass.odin"
output_pass="test_results/c015_results/c015_fixture_pass_results.txt"
./artifacts/olt --export-symbols "$FIXTURE_DIR/c015_fixture_pass.odin" \
    --db /tmp/c015_pass_test.db > "$output_pass" 2>&1
if ! grep -q "C015 \[dead_code\]" "$output_pass"; then
    echo "  PASS: No C015 violations (as expected)"
    ((passed_tests++))
else
    echo "  FAIL: Unexpected C015 violation"
    grep "C015" "$output_pass"
    ((failed_tests++))
fi
rm -f /tmp/c015_pass_test.db

# --- Fail fixture ---
echo "Testing: c015_fixture_fail.odin"
output_fail="test_results/c015_results/c015_fixture_fail_results.txt"
./artifacts/olt --export-symbols "$FIXTURE_DIR/c015_fixture_fail.odin" \
    --db /tmp/c015_fail_test.db > "$output_fail" 2>&1
if grep -q "C015 \[dead_code\]" "$output_fail"; then
    count=$(grep -c "C015 \[dead_code\]" "$output_fail")
    echo "  PASS: $count C015 violation(s) detected (as expected)"
    ((passed_tests++))
else
    echo "  FAIL: No C015 violations found (expected some)"
    cat "$output_fail"
    ((failed_tests++))
fi
rm -f /tmp/c015_fail_test.db

rm -f "$TOML"

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C015 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
