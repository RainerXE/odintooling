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

mkdir -p "$WORK/proj" && cp "$FIX"/*.odin "$WORK/proj/" && (cd "$WORK/proj" && git init -q .)
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

echo
echo "contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "🎉 olt's graph is a valid CodeGraph database" || echo "❌ contract broken"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
