#!/usr/bin/env bash
# run_gitignore_tests.sh — directory scans honour .gitignore (as git itself reads it).
#
# Builds a throwaway git repository with every awkward case, then checks which files olt
# scans, read from the graph's files table (the graph export uses the same scan as lint).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 2; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

mk() { mkdir -p "$(dirname "$1")"; printf 'package p\n\nbadName :: proc() {}\n' > "$1"; }

P="$WORK/proj"; mkdir -p "$P" && cd "$P" && git init -q . && git config user.email t@t && git config user.name t
printf 'build/\n*.gen.odin\n!keep.gen.odin\n/scratch/\nminimal\n' > .gitignore
mk main.odin
mk build/out.odin                 # ignored: directory pattern
mk types.gen.odin                 # ignored: glob
mk keep.gen.odin                  # NOT ignored: re-included by negation
mk scratch/tmp.odin               # ignored: anchored directory
mk nested/scratch/ok.odin         # NOT ignored: "/scratch/" is anchored to the root
mk sub/ok.odin
mk sub/local_only.odin            # ignored by sub/.gitignore (nested)
printf 'local_only.odin\n' > sub/.gitignore
mk examples/other/main.odin
mk examples/minimal/main.odin     # ignored by pattern AND tracked (git add -f): CodeGraph skips these
git add -A . >/dev/null 2>&1; git add -f examples/minimal/main.odin; git commit -q -m fixture

# files olt put in its graph for the given arguments (the graph is built from the same scan lint uses)
scanned() {
  rm -rf .codegraph
  "$OLT_BINARY" --export-symbols --db .codegraph/g.db "$@" >/dev/null 2>&1
  python3 - <<'PY'
import sqlite3
print(" ".join(sorted(r[0] for r in sqlite3.connect(".codegraph/g.db").execute("select path from files"))) + " ")
PY
}
want_set() { [ "$1" = "$2" ]; }

echo "== 1. inside a git repository, a directory scan skips ignored files"
GOT="$(cd "$P" && scanned .)"
WANT="examples/other/main.odin keep.gen.odin main.odin nested/scratch/ok.odin sub/ok.odin "
want_set "$GOT" "$WANT" && ok "scans exactly the files git does not ignore" || bad "got:  $GOT
                          want: $WANT"
case "$GOT" in *examples/minimal*) bad "a tracked file matching an ignore pattern is skipped" ;; *) ok "a tracked file that matches an ignore pattern is skipped (as CodeGraph does)" ;; esac

echo "== 2. --no-gitignore scans them all"
GOT="$(cd "$P" && scanned --no-gitignore .)"
for f in build/out.odin types.gen.odin scratch/tmp.odin sub/local_only.odin examples/minimal/main.odin; do
  case "$GOT" in *"$f"*) ok "--no-gitignore scans $f" ;; *) bad "--no-gitignore should scan $f" ;; esac
done

echo "== 3. a file named on the command line is never filtered"
GOT="$(cd "$P" && scanned build/out.odin)"
want_set "$GOT" "build/out.odin " && ok "explicit ignored file is scanned" || bad "got: $GOT"

echo "== 4. scanning from a subdirectory"
GOT="$(cd "$P/sub" && scanned .)"
case "$GOT" in *local_only*) bad "nested ignore honoured from a subdirectory (got: $GOT)" ;; *ok.odin*) ok "nested .gitignore honoured when scanning sub/" ;; *) bad "got: $GOT" ;; esac

echo "== 5. outside a git repository nothing is filtered"
cp -r "$P" "$WORK/plain" && rm -rf "$WORK/plain/.git"
GOT="$(cd "$WORK/plain" && scanned .)"
case "$GOT" in *build/out.odin*types.gen.odin*|*types.gen.odin*build/out.odin*) ok "no repo, no filtering" ;; *) bad "got: $GOT" ;; esac

echo
echo "gitignore: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "🎉 All gitignore tests passed!" || echo "❌ Some gitignore tests failed."
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
