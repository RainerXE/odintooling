#!/usr/bin/env bash
# run_c203_tests.sh — C203 defer scope trap tests

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/odin-lint"
FAIL_FIXTURE="$REPO_ROOT/tests/C203_COR_DEFER_SCOPE/c203_fixture_fail.odin"
PASS_FIXTURE="$REPO_ROOT/tests/C203_COR_DEFER_SCOPE/c203_fixture_pass.odin"

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

echo "🧪 C203 Defer Scope Trap Test Suite"
echo "====================================="

# ── Fail fixture: expect C203 violations ─────────────────────────────────────
echo ""
echo "── Fail fixture ──"
output=$("$BINARY" "$FAIL_FIXTURE" --rule C203 2>&1 || true)

count=$(echo "$output" | grep -c "C203" || true)
check "fail fixture produces C203 violations" "$([ "$count" -gt 0 ] && echo true || echo false)" "got $count"
check "member-assignment case detected"  "$(echo "$output" | grep -q "ctx.db"    && echo true || echo false)"
check "nested-if case detected"          "$(echo "$output" | grep -q "ctx.file"  && echo true || echo false)"
check "real-bug reproduction detected"   "$(echo "$output" | grep -q "type_ctx"  && echo true || echo false)"

# ── Pass fixture: expect zero C203 violations ─────────────────────────────────
echo ""
echo "── Pass fixture ──"
pass_output=$("$BINARY" "$PASS_FIXTURE" --rule C203 2>&1 || true)
pass_count=$(echo "$pass_output" | grep -c "C203" || true)
check "pass fixture has 0 C203 violations" "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

# ── Own codebase: must produce 0 violations ────────────────────────────────────
echo ""
echo "── Own codebase regression ──"
own_output=$("$BINARY" "$REPO_ROOT/src" --rule C203 2>&1 || true)
own_count=$(echo "$own_output" | grep -c "C203" || true)
check "own codebase produces 0 C203 violations" "$([ "$own_count" -eq 0 ] && echo true || echo false)" "got $own_count"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "====================================="
echo "C203 Test Summary"
echo "====================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All C203 tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
