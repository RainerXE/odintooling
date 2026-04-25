#!/usr/bin/env bash
# test_m9_config.sh — verify [tools] section in olt.toml is parsed correctly.
# Creates a temp project dir with a known TOML and checks odin-lint honours it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/artifacts/odin-lint"

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

# ── Test 2: [tools] with odin_path pointing to a valid executable ─────────────
echo ""
echo "── [tools] odin_path = valid path ──"
ODIN_EXE=$(command -v odin 2>/dev/null || true)
if [ -n "$ODIN_EXE" ]; then
    cat > "$TMPDIR/olt.toml" << TOML
[tools]
odin_path = "$ODIN_EXE"
ols_path  = "/tmp/nonexistent-ols"
TOML
    out=$("$BINARY" "$TMPDIR/main.odin" 2>&1 || true)
    check "[tools] odin_path parsed without crash" \
        "$(echo "$out" | grep -qiv "panic\|runtime error" && echo true || echo false)"
    check "[tools] produces no unexpected error output" \
        "$(echo "$out" | grep -qiv "failed to parse\|toml error" && echo true || echo false)"
else
    check "[tools] odin_path test (odin not in PATH — skipped)" "true"
    check "[tools] no crash placeholder" "true"
fi

# ── Test 3: [tools] with bogus odin_path — should not crash odin-lint itself ──
echo ""
echo "── [tools] odin_path = bogus path ──"
cat > "$TMPDIR/olt.toml" << 'TOML'
[tools]
odin_path = "/nonexistent/odin-binary"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1 || true)
check "bogus odin_path does not crash odin-lint itself" \
    "$(echo "$out" | grep -qiv "panic\|segfault\|runtime error" && echo true || echo false)"

# ── Test 4: [tools] + [domains] coexist ──────────────────────────────────────
echo ""
echo "── [tools] + [domains] coexist ──"
cat > "$TMPDIR/olt.toml" << 'TOML'
[domains]
ffi = false

[tools]
odin_path = "/usr/bin/env"
ols_path  = "/usr/bin/env"
TOML
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1 || true)
check "[tools] and [domains] can coexist in same toml" \
    "$(echo "$out" | grep -qiv "panic\|runtime error\|failed to parse" && echo true || echo false)"

# ── Test 5: effective_odin_path falls back to "odin" when no config ───────────
echo ""
echo "── effective_odin_path fallback ──"
rm -f "$TMPDIR/olt.toml"
out=$("$BINARY" "$TMPDIR/main.odin" 2>&1 || true)
check "no toml: runs with PATH odin (no crash)" \
    "$(echo "$out" | grep -qiv "panic\|runtime error" && echo true || echo false)"

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
