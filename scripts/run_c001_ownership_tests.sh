#!/usr/bin/env bash
# run_c001_ownership_tests.sh — C001 consults the whole-procedure ownership analysis.
#
# C001 alone only knows `return x` and `defer delete(x)`. With the analysis behind the graph it also stays
# quiet for an allocation that is returned inside a tuple or slice, stored into a field or a list, released
# on a path it cannot see, freed by a deferred block, or drawn from an arena or the temp allocator; and it
# still reports the ones that leak.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY, REPO_ROOT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
T="$REPO_ROOT/tests/C001_OWNERSHIP"

out="$("$OLT_BINARY" --rule C001 "$T/pass.odin" 2>&1)"
if echo "$out" | grep -q "C001 \["; then
  bad "handed-on or released allocations were reported"; echo "$out" | grep "C001 \[" | sed 's/^/      /'
else ok "allocations that are returned, stored, released or arena-backed are not reported"; fi

out="$("$OLT_BINARY" --rule C001 "$T/fail.odin" 2>&1)"
lines="$(echo "$out" | grep "C001 \[" | sed -E 's/.*odin:([0-9]+):.*/\1/' | sort -n | tr '\n' ' ')"
if [ "$lines" = "7 13 21 27 33 40 47 52 57 62 " ]; then ok "allocations that leak are still reported, bound or not (lines 7, 13, 21, 27, 33, 40, 47, 52, 57, 62)"
else bad "expected reports at lines 7 13 21 27 33 40 47 52 57 62, got: $lines"; echo "$out" | sed 's/^/      /'; fi

echo "c001 ownership: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
