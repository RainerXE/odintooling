#!/usr/bin/env bash
# run_ownership_tests.sh — allocation sites, ownership edges and memory roles in the graph.
#
# Exports a graph for tests/OWNERSHIP/ and compares it, exactly, with the expected tables
# in tests/OWNERSHIP/expected/. Also checks that the instantiates edges carry valid JSON and
# that the proc -> type edges land on the right types.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

cd "$WORK" || exit 2
"$OLT_BINARY" --export-symbols --db g.db "$REPO/tests/OWNERSHIP" >/dev/null 2>&1
[ -f g.db ] || { echo "no graph produced"; exit 1; }

# dump <name> -> prints the table for `name`, one row per line, tab-separated
dump() {
python3 - "$1" <<'PY'
import sqlite3, sys, json
c = sqlite3.connect("g.db")
what = sys.argv[1]
if what == "sites":
    q = """select p.name, a.line, a.api, coalesce(a.elem_type,''), a.allocator_kind,
                  coalesce(a.var_name,''), a.disposition
           from odin_alloc_site a join nodes p on p.id=a.proc_id order by a.line, a.col"""
    for r in c.execute(q): print("\t".join(str(x) for x in r))
elif what == "roles":
    q = """select n.name, o.memory_role from odin_node_info o join nodes n on n.id=o.node_id
           where n.kind='function' order by n.start_line"""
    for r in c.execute(q): print("\t".join(r))
elif what == "edges":
    q = """select s.name, t.name, e.metadata from edges e join nodes s on s.id=e.source
           join nodes t on t.id=e.target where e.kind='instantiates' order by e.line"""
    for n, t, m in c.execute(q):
        d = json.loads(m)                      # must be valid JSON
        print("\t".join([n, t, d["ownership"], d["allocator"], d["api"]]))
PY
}

for t in sites roles edges; do
  if diff <(dump $t) "$REPO/tests/OWNERSHIP/expected/$t.tsv" >"$WORK/$t.diff"; then
    ok "$t match the expected table"
  else
    bad "$t differ from tests/OWNERSHIP/expected/$t.tsv"; sed 's/^/      /' "$WORK/$t.diff"
  fi
done

# re-exporting must not duplicate anything (incremental run)
"$OLT_BINARY" --export-symbols --db g.db "$REPO/tests/OWNERSHIP" >/dev/null 2>&1
for t in sites edges; do
  if diff <(dump $t) "$REPO/tests/OWNERSHIP/expected/$t.tsv" >/dev/null; then
    ok "re-export leaves $t unchanged"
  else
    bad "re-export changed $t"
  fi
done

echo "ownership: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
