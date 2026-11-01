#!/usr/bin/env bash
# run_c001_defer_block_tests.sh — C001 understands `defer { delete(a); delete(b) }`.
#
# Found by scripts/crosscheck_c001.py: the rule only recognised a single `defer delete(x)`, so every
# allocation released by a deferred block was reported as a leak (6 such reports in Odin's own tests).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY, REPO_ROOT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
T="$REPO_ROOT/tests/C001_DEFER_BLOCK"

out="$("$OLT_BINARY" --rule C001 "$T/pass.odin" 2>&1)"
if echo "$out" | grep -q "C001"; then bad "allocations freed in a deferred block were reported"; echo "$out" | sed 's/^/      /'
else ok "allocations freed in a deferred block are not reported"; fi

out="$("$OLT_BINARY" --rule C001 "$T/fail.odin" 2>&1)"
n=$(echo "$out" | grep -c "C001 \[")
lines="$(echo "$out" | grep "C001 \[" | sed -E 's/.*odin:([0-9]+):.*/\1/' | tr '\n' ' ')"
if [ "$n" = 1 ] && [ "$lines" = "6 " ]; then ok "only the allocation the block does not free is reported (line 6)"
else bad "expected exactly one report, at line 6; got $n at: $lines"; echo "$out" | sed 's/^/      /'; fi

echo "c001 defer block: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
