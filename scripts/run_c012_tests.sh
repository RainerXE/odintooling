#!/bin/bash
# C012 Semantic Naming Test Suite — S1-S3 (tree-sitter) + T1 + T3 (graph-enriched)

LINT=./artifacts/odin-lint
FIXTURE_DIR=tests/C012_SEM_NAMING
DB=/tmp/c012_test_graph.db
OUT=test_results/c012_results
mkdir -p "$OUT"

passed=0
failed=0

check_pass() {
    local label=$1 file=$2
    local out="$OUT/${label}.txt"
    $LINT "$file" --enable-c012 --db="$DB" > "$out" 2>&1
    if ! grep -q "C012 \[" "$out"; then
        echo "  PASS: No C012 violations (as expected) — $label"
        ((passed++))
    else
        echo "  FAIL: Unexpected C012 violation — $label"
        grep "C012 \[" "$out"
        ((failed++))
    fi
}

check_fail() {
    local label=$1 file=$2 min_count=${3:-1}
    local out="$OUT/${label}.txt"
    $LINT "$file" --enable-c012 --db="$DB" > "$out" 2>&1
    local count
    count=$(grep "C012 \[" "$out" 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + 0))
    if [ "$count" -ge "$min_count" ]; then
        echo "  PASS: $count C012 violation(s) detected — $label"
        ((passed++))
    else
        echo "  FAIL: Expected >=$min_count C012 violations, got $count — $label"
        cat "$out"
        ((failed++))
    fi
}

echo "C012 Semantic Naming Tests"
echo "=========================="
echo ""
echo "--- Setup: build graph for T3 (tags get_scratch as allocator) ---"
rm -f "$DB"
# Export symbols from the T3 fixture so get_scratch gets into the graph.
# We manually update its memory_role to 'allocator' to simulate T3 scenario.
$LINT "$FIXTURE_DIR" --export-symbols --db="$DB" 2>/dev/null
sqlite3 "$DB" "UPDATE nodes SET memory_role='allocator', return_type='mem.Allocator' WHERE name='get_scratch';" 2>/dev/null
echo "  Graph built and get_scratch tagged as allocator."

echo ""
echo "--- T1: explicit mem.Allocator variable naming ---"
check_pass "t1_pass" "$FIXTURE_DIR/c012_t1_pass.odin"
check_fail "t1_fail" "$FIXTURE_DIR/c012_t1_fail.odin" 3

echo ""
echo "--- T3: allocator-return without _owned suffix ---"
check_pass "t3_pass" "$FIXTURE_DIR/c012_t3_pass.odin"
check_fail "t3_fail" "$FIXTURE_DIR/c012_t3_fail.odin" 1

echo ""
echo "=========================="
total=$((passed + failed))
echo "Total: $total  Passed: $passed  Failed: $failed"
if [ $failed -eq 0 ]; then
    echo "All C012 tests passed!"
    exit 0
else
    echo "Some C012 tests FAILED."
    exit 1
fi
