#!/usr/bin/env bash
# test_codegraph_contract.sh — olt's graph database must be a database a real
# CodeGraph can open, query and sync.
#
# Builds a graph with olt from tests/CODEGRAPH_CONTRACT, then drives a real
# CodeGraph over it. Run it after every refresh of ffi/codegraph/schema.sql, and in CI
# against the CodeGraph release you target.
#
#   CODEGRAPH_BIN="node /path/to/codegraph/dist/bin/codegraph.js" ./scripts/test_codegraph_contract.sh
#   CODEGRAPH_BIN=codegraph ./scripts/test_codegraph_contract.sh      # an installed codegraph
#
# Needs the olt binary (scripts/build.sh), sqlite3 NOT required.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY, REPO_ROOT
CG="${CODEGRAPH_BIN:-codegraph}"
export CODEGRAPH_TELEMETRY=0
FIX="$REPO_ROOT/tests/CODEGRAPH_CONTRACT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()   { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1 — $3"; fi; }

command -v ${CG%% *} >/dev/null 2>&1 || { echo "codegraph not found (set CODEGRAPH_BIN)"; exit 2; }
WANT_VER="$(grep -E '^CODEGRAPH_SCHEMA_VERSION' "$REPO_ROOT/src/core/graph_schema.odin" | grep -oE '[0-9]+' | head -1)"
echo "CodeGraph: $($CG --version 2>/dev/null | head -1)   expected schema version: $WANT_VER"

mkdir -p "$WORK/proj" && cp -r "$FIX"/. "$WORK/proj/" && (cd "$WORK/proj" && git init -q .)
cd "$WORK/proj"

echo "== 1. olt writes a CodeGraph database"
"$OLT_BINARY" --codegraph-init . >"$WORK/init.log" 2>&1
check "olt --codegraph-init succeeds" '[ -f .codegraph/codegraph.db ]' "$(tail -3 "$WORK/init.log")"

echo "== 2. CodeGraph opens and reads it"
$CG status >"$WORK/status.log" 2>&1
check "status opens the database"                 'grep -q "Index Statistics" "$WORK/status.log"' "$(head -5 "$WORK/status.log")"
check "status reports no interrupted run"         '! grep -q "interrupted run" "$WORK/status.log"' "unresolved refs are not marked failed"
check "kinds are CodeGraph kinds (function, enum, struct, union)" \
      'grep -q "function" "$WORK/status.log" && grep -q "enum" "$WORK/status.log" && grep -q "struct" "$WORK/status.log" && grep -q "union" "$WORK/status.log"' "$(grep -A12 'Nodes by Kind' "$WORK/status.log")"
$CG callers helper >"$WORK/callers.log" 2>&1
check "callers(helper) = main, outer and inner" \
      'grep -q "Callers of \"helper\" (3)" "$WORK/callers.log" && grep -qw "main" "$WORK/callers.log" && grep -qw "outer" "$WORK/callers.log" && grep -qw "inner" "$WORK/callers.log"' "$(head -14 "$WORK/callers.log")"
$CG callers after_nested >"$WORK/callers2.log" 2>&1
check "a call after a nested proc ends belongs to the outer proc, not the nested one" \
      'grep -q "Callers of \"after_nested\" (1)" "$WORK/callers2.log" && grep -qw "outer" "$WORK/callers2.log" && ! grep -qw "inner" "$WORK/callers2.log"' "$(head -8 "$WORK/callers2.log")"
$CG callers util >"$WORK/callers3.log" 2>&1
check "pkg.fn() through an import reaches the other package's procedure" \
      'grep -q "Callers of \"util\" (1)" "$WORK/callers3.log" && grep -qw "main" "$WORK/callers3.log"' "$(head -8 "$WORK/callers3.log")"
cgsql() { CG_DB=.codegraph/codegraph.db node -e "const {DatabaseSync}=require('node:sqlite');console.log(new DatabaseSync(process.env.CG_DB,{readOnly:true}).prepare(process.argv[1]).get().c)" "$1" 2>/dev/null; }
GROUP_REFS="$(cgsql "select count(*) c from edges e join nodes s on s.id=e.source join nodes t on t.id=e.target where e.kind='references' and s.name='area' and t.name='area_point'")"
MEMBER_NODES="$(cgsql "select count(*) c from nodes where name='area_point' and kind='function'")"
check "a procedure group links to its member (references edge)" '[ "$GROUP_REFS" = 1 ]' "area -> area_point references edges: '$GROUP_REFS'"
check "a group member is indexed once, not again from inside the group's braces" '[ "$MEMBER_NODES" = 1 ]' "area_point function nodes: '$MEMBER_NODES'"
OWN_EDGES="$(cgsql "select count(*) c from edges e join nodes s on s.id=e.source join nodes t on t.id=e.target where e.kind='instantiates' and s.name='make_point' and t.name='Point' and json_extract(e.metadata,'$.ownership')='returned' and json_extract(e.metadata,'$.allocator')='default'")"
check "an allocation is an instantiates edge with ownership metadata" '[ "$OWN_EDGES" = 1 ]' "make_point -> Point instantiates edges with the expected metadata: '$OWN_EDGES'"
$CG query Colour >"$WORK/query.log" 2>&1
check "query finds the enum"                       'grep -qi "Colour" "$WORK/query.log"' "$(head -5 "$WORK/query.log")"

echo "== 3. CodeGraph syncs it without schema errors (the migration that used to fail)"
$CG sync >"$WORK/sync.log" 2>&1; rc=$?
check "sync exits 0"                               '[ $rc -eq 0 ]' "exit $rc: $(tail -3 "$WORK/sync.log")"
check "no 'duplicate column' / 'could not open'"   '! grep -qiE "duplicate column|could not open" "$WORK/sync.log"' "$(grep -iE 'duplicate|could not open' "$WORK/sync.log")"
GOT_VER="$(CG_DB=.codegraph/codegraph.db node -e "const {DatabaseSync}=require('node:sqlite');console.log(new DatabaseSync(process.env.CG_DB,{readOnly:true}).prepare('select max(version) v from schema_versions').get().v)" 2>/dev/null)"
check "schema version is the expected one ($WANT_VER)" '[ "$GOT_VER" = "$WANT_VER" ]' "found '$GOT_VER'"
$CG status >"$WORK/status2.log" 2>&1
check "status still opens after sync"              'grep -q "Index Statistics" "$WORK/status2.log"' "$(head -5 "$WORK/status2.log")"
# CodeGraph's sync re-extracts the files it sees as modified and replaces their rows, olt's
# odin_* data (roles, ownership) with them. An olt re-export puts it back.
"$OLT_BINARY" --export-symbols --db .codegraph/codegraph.db . >/dev/null 2>&1
OWN_BACK="$(cgsql "select count(*) c from edges where kind='instantiates'")"
SITES_BACK="$(cgsql "select count(*) c from odin_alloc_site")"
check "an olt re-export after a CodeGraph sync restores the ownership data" '[ "$OWN_BACK" = 1 ] && [ "$SITES_BACK" = 1 ]' "instantiates=$OWN_BACK sites=$SITES_BACK"

echo
echo "contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "🎉 olt's graph is a valid CodeGraph database" || echo "❌ contract broken"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
