#!/usr/bin/env bash
# run_c201_resolve_tests.sh — C201 follows a qualified call into the package it goes to.
#
# C201 reports a bare call whose error result is discarded. It used to know only a short list of standard-library
# calls and procedures of the same package; `lib.risky()` or `os.set_env(...)` went unnoticed. It now reads the
# declaration from the imported package's source: project packages (relative imports) always, core:/base:/vendor:
# when an Odin installation is found (ODIN_ROOT, or `odin root`).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY, REPO_ROOT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
FIX="$REPO_ROOT/tests/C201_RESOLVE/main.odin"

lines_of() { grep "C201 \[" | sed -E 's/.*main\.odin:([0-9]+):.*/\1/' | sort -n | tr '\n' ' '; }
flagged()         { "$OLT_BINARY" --rule C201 "$FIX" 2>&1 | lines_of; }
flagged_no_odin() { env -u ODIN_ROOT PATH=/usr/bin:/bin "$OLT_BINARY" --rule C201 "$FIX" 2>&1 | lines_of; }

# 1. no Odin installation: the project's own packages still resolve, the standard library falls back to the curated list
no_odin="$(flagged_no_odin)"
[ "$no_odin" = "11 13 15 17 " ] && ok "without an Odin installation: project packages, a group and an alias are resolved (lines 11 13 15 17)" \
                                || bad "without Odin expected lines '11 13 15 17', got '$no_odin'"

# 2. with one: core:os is read too (set_env is not on the curated list), stream output and allocator errors stay quiet
have_odin=false
if [ -n "${ODIN_ROOT:-}" ] && [ -d "$ODIN_ROOT/core" ]; then have_odin=true
elif command -v odin >/dev/null 2>&1 && [ -d "$(odin root 2>/dev/null)/core" ]; then have_odin=true; fi
if $have_odin; then
  with_odin="$(flagged)"
  [ "$with_odin" = "11 13 15 17 22 " ] && ok "with an Odin installation: os.set_env is reported too (line 22); io.write_string and mem.free are not" \
                                       || bad "with Odin expected lines '11 13 15 17 22', got '$with_odin'"
else
  echo "  ⏭  SKIP: no Odin installation found (set ODIN_ROOT) — the standard-library case is not tested"
fi

# 3. the curated list is untouched
d="$(mktemp -d)"; printf 'package m\nimport "core:os"\nmain :: proc() {\n\tos.open("x")\n}\n' > "$d/c.odin"
out="$("$OLT_BINARY" --rule C201 "$d/c.odin" 2>&1)"
echo "$out" | grep -q "error return of 'os.open'" && ok "the curated list still reports os.open" || bad "os.open is no longer reported: $out"
rm -rf "$d"

# 4. no invalid memory access. A read of freed memory returns the right bytes by luck on some platforms (it did on Linux while
# the imports map was freed too early) and garbage on others (macOS), so this class of bug can only be seen with a checker.
if command -v valgrind >/dev/null 2>&1; then
  vg="$(env -u ODIN_ROOT valgrind -q --error-limit=no --num-callers=8 "$OLT_BINARY" --rule C201 "$FIX" 2>&1)"
  bad_n="$(echo "$vg" | grep -c "Invalid read\|Invalid write\|Invalid free")"
  [ "$bad_n" = 0 ] && ok "no invalid memory accesses under valgrind" || { bad "valgrind reports $bad_n invalid memory accesses"; echo "$vg" | grep -A8 "Invalid" | head -30 | sed 's/^/      /'; }
else
  echo "  ⏭  SKIP: valgrind not installed — memory safety of the resolver is not checked here"
fi

echo "c201 resolve: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
