#!/usr/bin/env bash
# run_c021_c023_tests.sh — Go-compatibility rule tests (C021/C022/C023)
# These rules require [domains] go_migration = true in olt.toml, or explicit --rule flag.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/olt"

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

echo "🧪 C021/C022/C023 Go-Compat Test Suite"
echo "====================================="

# ── C021: Go fmt calls ──
echo ""
echo "── C021 fmt calls ──"
c021_fail="$REPO_ROOT/tests/C021_GO_FMT_CALL/c021_fixture_fail.odin"
c021_pass="$REPO_ROOT/tests/C021_GO_FMT_CALL/c021_fixture_pass.odin"

c021_out=$("$BINARY" "$c021_fail" --rule C021 2>&1 || true)
c021_count=$(echo "$c021_out" | grep -c "C021" || true)
check "C021 fail fixture produces violations"  "$([ "$c021_count" -gt 0 ] && echo true || echo false)" "got $c021_count"
check "fmt.Println detected"                   "$(echo "$c021_out" | grep -q "Println" && echo true || echo false)"
check "fmt.Printf detected"                    "$(echo "$c021_out" | grep -q "Printf"  && echo true || echo false)"

c021_pass_out=$("$BINARY" "$c021_pass" --rule C021 2>&1 || true)
c021_pass_count=$(echo "$c021_pass_out" | grep -c "C021" || true)
check "C021 pass fixture 0 violations"         "$([ "$c021_pass_count" -eq 0 ] && echo true || echo false)" "got $c021_pass_count"

# ── C022: Go range loop ──
echo ""
echo "── C022 range loop ──"
c022_fail="$REPO_ROOT/tests/C022_GO_RANGE_LOOP/c022_fixture_fail.odin"
c022_pass="$REPO_ROOT/tests/C022_GO_RANGE_LOOP/c022_fixture_pass.odin"

c022_out=$("$BINARY" "$c022_fail" --rule C022 2>&1 || true)
c022_count=$(echo "$c022_out" | grep -c "C022" || true)
check "C022 fail fixture produces violations"  "$([ "$c022_count" -gt 0 ] && echo true || echo false)" "got $c022_count"
check "range keyword detected"                 "$(echo "$c022_out" | grep -qi "range" && echo true || echo false)"

c022_pass_out=$("$BINARY" "$c022_pass" --rule C022 2>&1 || true)
c022_pass_count=$(echo "$c022_pass_out" | grep -c "C022" || true)
check "C022 pass fixture 0 violations"         "$([ "$c022_pass_count" -eq 0 ] && echo true || echo false)" "got $c022_pass_count"

# ── C023: C-style deref ──
echo ""
echo "── C023 C-style dereference ──"
c023_fail="$REPO_ROOT/tests/C023_GO_DEREF/c023_fixture_fail.odin"
c023_pass="$REPO_ROOT/tests/C023_GO_DEREF/c023_fixture_pass.odin"

c023_out=$("$BINARY" "$c023_fail" --rule C023 2>&1 || true)
c023_count=$(echo "$c023_out" | grep -c "C023" || true)
check "C023 fail fixture produces violations"  "$([ "$c023_count" -gt 0 ] && echo true || echo false)" "got $c023_count"
check "postfix ^ suggested"                    "$(echo "$c023_out" | grep -q '\^' && echo true || echo false)"

c023_pass_out=$("$BINARY" "$c023_pass" --rule C023 2>&1 || true)
c023_pass_count=$(echo "$c023_pass_out" | grep -c "C023" || true)
check "C023 pass fixture 0 violations"         "$([ "$c023_pass_count" -eq 0 ] && echo true || echo false)" "got $c023_pass_count"

# ── Domain gate: off by default without explicit --rule ──
echo ""
echo "── Domain gate: go_migration off by default ──"
default_out=$("$BINARY" "$c021_fail" 2>&1 || true)
default_count=$(echo "$default_out" | grep -c "C021" || true)
check "C021 NOT fired without --rule (go_migration domain off)" \
    "$([ "$default_count" -eq 0 ] && echo true || echo false)" "got $default_count"

# ── Own codebase regression: 0 violations even with explicit flag ──
echo ""
echo "── Own codebase regression ──"
own_out=$("$BINARY" "$REPO_ROOT/src" --rule C021,C022,C023 2>&1 || true)
own_count=$(echo "$own_out" | grep -c "C02[123]" || true)
check "own codebase 0 C021/C022/C023 violations" \
    "$([ "$own_count" -eq 0 ] && echo true || echo false)" "got $own_count"

# ── Summary ──
echo ""
echo "====================================="
echo "C021/C022/C023 Test Summary: Passed=$PASS  Failed=$FAIL"
echo "====================================="
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All Go-compat tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
