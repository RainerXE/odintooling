#!/usr/bin/env bash
# run_c025_tests.sh — C025 append-missing-addr tests

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/olt"
FAIL_FIXTURE="$REPO_ROOT/tests/C025_COR_APPEND_ADDR/c025_fixture_fail.odin"
PASS_FIXTURE="$REPO_ROOT/tests/C025_COR_APPEND_ADDR/c025_fixture_pass.odin"

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

echo "🧪 C025 Append-Missing-Addr Test Suite"
echo "====================================="

# ── Fail fixture ──
echo ""
echo "── Fail fixture ──"
output=$("$BINARY" "$FAIL_FIXTURE" --rule C025 2>&1 || true)

count=$(echo "$output" | grep -c "C025" || true)
check "fail fixture produces C025 violations"  "$([ "$count" -gt 0 ] && echo true || echo false)" "got $count"
check "message mentions address-of"            "$(echo "$output" | grep -qi "&" && echo true || echo false)"
check "'items' flagged"                        "$(echo "$output" | grep -q "items" && echo true || echo false)"

# ── Pass fixture ──
echo ""
echo "── Pass fixture ──"
pass_output=$("$BINARY" "$PASS_FIXTURE" --rule C025 2>&1 || true)
pass_count=$(echo "$pass_output" | grep -c "C025" || true)
check "pass fixture has 0 C025 violations" "$([ "$pass_count" -eq 0 ] && echo true || echo false)" "got $pass_count"

# ── Domain gate: off by default (would FP on ^[dynamic]T params without type info) ──
echo ""
echo "── Domain gate: go_migration off by default ──"
default_output=$("$BINARY" "$REPO_ROOT/src" 2>&1 || true)
default_count=$(echo "$default_output" | grep -c "C025" || true)
check "C025 NOT fired in default scan (go_migration domain off)" \
    "$([ "$default_count" -eq 0 ] && echo true || echo false)" "got $default_count"

# ── Summary ──
echo ""
echo "====================================="
echo "C025 Test Summary: Passed=$PASS  Failed=$FAIL"
echo "====================================="
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All C025 tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
