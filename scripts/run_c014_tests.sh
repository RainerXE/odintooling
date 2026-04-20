#!/bin/bash

# C014 Test Runner — private procs with zero callers (dead code, opt-in)
#
# C014 is a graph-query rule: requires --export-symbols to build the call graph
# first, then queries it for private procs with no incoming call edges.
# Enabled via [domains] dead_code = true in odin-lint.toml.
#
# A temporary odin-lint.toml is placed in the fixture directory before each run
# and cleaned up afterwards so the dead_code domain is active.

echo "Running C014 Test Suite..."
echo "=========================="
mkdir -p test_results/c014_results

FIXTURE_DIR="tests/C014_DEA_UNUSEDPROC"
TOML="$FIXTURE_DIR/odin-lint.toml"

# Write the enabling toml into the fixture directory.
cat > "$TOML" <<'EOF'
[domains]
dead_code = true
EOF

total_tests=2
passed_tests=0
failed_tests=0

# --- Pass fixture ---
echo "Testing: c014_fixture_pass.odin"
output_pass="test_results/c014_results/c014_fixture_pass_results.txt"
./artifacts/odin-lint --export-symbols "$FIXTURE_DIR/c014_fixture_pass.odin" \
    --db /tmp/c014_pass_test.db > "$output_pass" 2>&1
if ! grep -q "C014 \[dead_code\]" "$output_pass"; then
    echo "  PASS: No C014 violations (as expected)"
    ((passed_tests++))
else
    echo "  FAIL: Unexpected C014 violation"
    grep "C014" "$output_pass"
    ((failed_tests++))
fi
rm -f /tmp/c014_pass_test.db

# --- Fail fixture ---
echo "Testing: c014_fixture_fail.odin"
output_fail="test_results/c014_results/c014_fixture_fail_results.txt"
./artifacts/odin-lint --export-symbols "$FIXTURE_DIR/c014_fixture_fail.odin" \
    --db /tmp/c014_fail_test.db > "$output_fail" 2>&1
if grep -q "C014 \[dead_code\]" "$output_fail"; then
    count=$(grep -c "C014 \[dead_code\]" "$output_fail")
    echo "  PASS: $count C014 violation(s) detected (as expected)"
    ((passed_tests++))
else
    echo "  FAIL: No C014 violations found (expected some)"
    cat "$output_fail"
    ((failed_tests++))
fi
rm -f /tmp/c014_fail_test.db

# Cleanup the temp toml.
rm -f "$TOML"

echo ""
echo "=========================="
echo "Total: $total_tests  Passed: $passed_tests  Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo "All C014 tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
