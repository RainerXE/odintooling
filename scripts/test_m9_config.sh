#!/usr/bin/env bash
# test_m9_config.sh — verify olt.toml sections are read, and settings that were removed are reported.
# Creates a temp project dir with a known TOML and checks odin-lint honours it.

set -uo pipefail
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

echo "🧪 M9 Config Test Suite"
echo "========================"

# ── Set up temp project ───────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Minimal Odin source file
cat > "$TMPDIR/main.odin" << 'ODIN'
package main
main :: proc() {}
ODIN

# ── Test 1: no olt.toml — default config (no [tools] section) ──────────
echo ""
echo "── No config file ──"
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1 || true)
check "runs without error when no toml present" \
    "$(echo "$out" | grep -qiv "panic\|runtime error" && echo true || echo false)"

# ── Test 2: [tools] ols_path is read ───────────────────────────────────────────
echo ""
echo "── [tools] ols_path ──"
cat > "$TMPDIR/olt.toml" << 'TOML'
[tools]
ols_path = "/tmp/nonexistent-ols"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1); rc=$?
check "[tools] ols_path is accepted: no warning, clean exit" \
    "$([ "$rc" = 0 ] && ! echo "$out" | grep -qi "warning" && echo true || echo false)" "rc=$rc: $out"

# ── Test 3: [tools] + [domains] coexist ──────────────────────────────────────
echo ""
echo "── [tools] + [domains] coexist ──"
cat > "$TMPDIR/olt.toml" << 'TOML'
[domains]
ffi = false

[tools]
ols_path = "/usr/bin/env"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1); rc=$?
check "[tools] and [domains] can coexist in the same toml" \
    "$([ "$rc" = 0 ] && ! echo "$out" | grep -qi "warning" && echo true || echo false)" "rc=$rc: $out"

# ── Test 4: settings that were removed because nothing read them ──────────────
# [target] odin_version and [tools] odin_path used to be accepted and ignored. An olt.toml that still has them
# must keep working (a warning, same result), and the warning must say what to do.
echo ""
echo "── removed settings: [target] odin_version, [tools] odin_path ──"
cat > "$TMPDIR/olt.toml" << 'TOML'
[target]
odin_version = "dev-2026-04"

[tools]
odin_path = "/nonexistent/odin-binary"
ols_path  = "/usr/bin/env"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1); rc=$?
check "an olt.toml with the removed settings still runs (exit 0)" "$([ "$rc" = 0 ] && echo true || echo false)" "rc=$rc"
check "[target] is reported as removed" \
    "$(echo "$out" | grep -q "section \[target\] was removed" && echo true || echo false)" "$out"
check "[tools] odin_path is reported as removed" \
    "$(echo "$out" | grep -q "key 'odin_path' in \[tools\] was removed" && echo true || echo false)" "$out"
check "the valid ols_path next to it draws no warning" \
    "$(echo "$out" | grep -q "ols_path" && echo false || echo true)" "$out"
check "nothing crashes" "$(echo "$out" | grep -qi "panic\|segfault\|runtime error" && echo false || echo true)"

# a key that never existed is still just an unknown key
cat > "$TMPDIR/olt.toml" << 'TOML'
[tools]
odin_pth = "/x"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1)
check "a mistyped key is still reported as unknown" \
    "$(echo "$out" | grep -q "unknown key 'odin_pth' in \[tools\]" && echo true || echo false)" "$out"
rm -f "$TMPDIR/olt.toml"

# ── Test 5: no config at all ──────────────────────────────────────────────────
echo ""
echo "── no config ──"
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1); rc=$?
check "no toml: clean run" "$([ "$rc" = 0 ] && ! echo "$out" | grep -qi "warning\|panic" && echo true || echo false)" "rc=$rc"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================"
echo "M9 Config Test Summary"
echo "========================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 All M9 config tests passed!"
    exit 0
else
    echo "❌ $FAIL test(s) failed."
    exit 1
fi
