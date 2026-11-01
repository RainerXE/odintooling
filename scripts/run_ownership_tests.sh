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

# Export from inside a copy of the fixture, as a user would from their project root: the package
# and import paths are then in the same (project-relative) form, which qualified calls need.
mkdir -p "$WORK/proj" && cp -r "$REPO/tests/OWNERSHIP"/. "$WORK/proj/" && rm -rf "$WORK/proj/expected"
cd "$WORK/proj" || exit 2
export_graph() { "$OLT_BINARY" --export-symbols --db .codegraph/g.db . >/dev/null 2>&1; }
export_graph
[ -f .codegraph/g.db ] || { echo "no graph produced"; exit 1; }

# dump <name> -> prints the table for `name`, one row per line, tab-separated
dump() {
python3 - "$1" <<'PY'
import sqlite3, sys, json
import os
c = sqlite3.connect(".codegraph/g.db")
what = sys.argv[1]
if what == "sites":
    q = """select p.name, a.line, a.api, coalesce(a.elem_type,''), a.allocator_kind,
                  coalesce(a.var_name,''), a.disposition
           from odin_alloc_site a join nodes p on p.id=a.proc_id order by p.file_path, a.line, a.col"""
    for r in c.execute(q): print("\t".join(str(x) for x in r))
elif what == "roles":
    q = """select n.name, o.memory_role from odin_node_info o join nodes n on n.id=o.node_id
           where n.kind='function' order by n.file_path, n.start_line"""
    for r in c.execute(q): print("\t".join(r))
elif what == "edges":
    q = """select s.name, t.name, e.metadata from edges e join nodes s on s.id=e.source
           join nodes t on t.id=e.target where e.kind='instantiates' order by s.file_path, e.line"""
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
export_graph
for t in sites edges; do
  if diff <(dump $t) "$REPO/tests/OWNERSHIP/expected/$t.tsv" >/dev/null; then
    ok "re-export leaves $t unchanged"
  else
    bad "re-export changed $t"
  fi
done

echo "ownership: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
