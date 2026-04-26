#!/usr/bin/env bash
# run_c029_c033_tests.sh — Stdlib Safety rule tests (C029/C033)
# Requires [domains] stdlib_safety = true in olt.toml, or explicit --rule flag.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_platform.sh"
BINARY="$OLT_BINARY"

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

echo "🧪 C029/C033 Stdlib Safety Test Suite"
echo "====================================="

# ── C029: stdlib alloc without defer delete ──
echo ""
echo "── C029 stdlib alloc ──"
c029_fail="$REPO_ROOT/tests/C029_STD_ALLOC/c029_fixture_fail.odin"
c029_pass="$REPO_ROOT/tests/C029_STD_ALLOC/c029_fixture_pass.odin"

c029_out=$("$BINARY" "$c029_fail" --rule C029 2>&1 || true)
c029_count=$(echo "$c029_out" | grep -c "C029" || true)
check "C029 fail fixture detects violations"       "$([ "$c029_count" -ge 5 ] && echo true || echo false)" "got $c029_count"
check "strings.split detected"                     "$(echo "$c029_out" | grep -q "parts"  && echo true || echo false)"
check "fmt.aprintf detected"                       "$(echo "$c029_out" | grep -q "msg"    && echo true || echo false)"
check "os.read_entire_file_from_path detected"     "$(echo "$c029_out" | grep -q "data"   && echo true || echo false)"

c029_pass_out=$("$BINARY" "$c029_pass" --rule C029 2>&1 || true)
c029_pass_count=$(echo "$c029_pass_out" | grep -c "C029" || true)
check "C029 pass fixture 0 violations"             "$([ "$c029_pass_count" -eq 0 ] && echo true || echo false)" "got $c029_pass_count"

# ── C033: strings.Builder without destroy ──
echo ""
echo "── C033 strings.Builder ──"
c033_fail="$REPO_ROOT/tests/C033_STD_BUILDER/c033_fixture_fail.odin"
c033_pass="$REPO_ROOT/tests/C033_STD_BUILDER/c033_fixture_pass.odin"

c033_out=$("$BINARY" "$c033_fail" --rule C033 2>&1 || true)
c033_count=$(echo "$c033_out" | grep -c "C033" || true)
check "C033 fail fixture detects violations"       "$([ "$c033_count" -ge 2 ] && echo true || echo false)" "got $c033_count"
check "builder_destroy message present"            "$(echo "$c033_out" | grep -q "builder_destroy" && echo true || echo false)"

c033_pass_out=$("$BINARY" "$c033_pass" --rule C033 2>&1 || true)
c033_pass_count=$(echo "$c033_pass_out" | grep -c "C033" || true)
check "C033 pass fixture 0 violations"             "$([ "$c033_pass_count" -eq 0 ] && echo true || echo false)" "got $c033_pass_count"

# ── Domain gate: off by default ──
echo ""
echo "── Domain gate: stdlib_safety off by default ──"
default_out=$("$BINARY" "$c029_fail" 2>&1 || true)
default_count=$(echo "$default_out" | grep -c "C029" || true)
check "C029 NOT fired in default scan"             "$([ "$default_count" -eq 0 ] && echo true || echo false)" "got $default_count"

# ── Own codebase regression ──
echo ""
echo "── Own codebase regression ──"
own_out=$("$BINARY" "$REPO_ROOT/src" --rule C029,C033 2>&1 || true)
own_count=$(echo "$own_out" | grep -c "C02[93]\|C033" || true)
check "own codebase 0 C029/C033 violations"        "$([ "$own_count" -eq 0 ] && echo true || echo false)" "got $own_count"

# ── Summary ──
echo ""
echo "====================================="
echo "C029/C033 Test Summary: Passed=$PASS  Failed=$FAIL"
echo "====================================="
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All stdlib safety tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
