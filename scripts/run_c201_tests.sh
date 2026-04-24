#!/usr/bin/env bash
# run_c201_tests.sh — C201 unchecked error return tests

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/odin-lint"
FAIL_FIXTURE="$REPO_ROOT/tests/C201_COR_UNCHECKED/c201_fixture_fail.odin"
PASS_FIXTURE="$REPO_ROOT/tests/C201_COR_UNCHECKED/c201_fixture_pass.odin"

PASS=0
FAIL=0

check() {
    local label="$1"
    local condition="$2"
    local detail="${3:-}"
    if [ "$condition" = "true" ]; then
        echo "  ✅ PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $label${detail:+ — $detail}"
        FAIL=$((FAIL + 1))
    fi
}

echo "🧪 C201 Unchecked Error Return Test Suite"
echo "=========================================="

# ── Fail fixture: expect violations ──────────────────────────────────────────
echo ""
echo "── Fail fixture ──"
output=$("$BINARY" "$FAIL_FIXTURE" --rule C201 2>&1 || true)

count=$(echo "$output" | grep -c "C201" || true)
check "fail fixture produces C201 violations" "$([ "$count" -gt 0 ] && echo true || echo false)" "got $count"
check "os.open detected"   "$(echo "$output" | grep -q "open" && echo true || echo false)"
check "os.write detected"  "$(echo "$output" | grep -q "write" && echo true || echo false)"
check "net.dial_tcp detected" "$(echo "$output" | grep -q "dial_tcp" && echo true || echo false)"

# ── Pass fixture: expect zero violations ─────────────────────────────────────
echo ""
echo "── Pass fixture ──"
pass_output=$("$BINARY" "$PASS_FIXTURE" --rule C201 2>&1 || true)
pass_count=$(echo "$pass_output" | grep -c "C201" || true)
check "pass fixture has 0 C201 violations" "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "C201 Test Summary"
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All C201 tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
