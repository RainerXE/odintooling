#!/usr/bin/env bash
# update_codegraph_schema.sh — refresh the vendored CodeGraph schema.
#
#   ./scripts/update_codegraph_schema.sh [REF]      # REF: tag, branch or commit of colbymchenry/codegraph (default: main)
#
# Rewrites ffi/codegraph/schema.sql, the table in ffi/codegraph/README.md and
# CODEGRAPH_SCHEMA_VERSION in src/core/graph_schema.odin to match that ref, then tells
# you to rebuild and run scripts/test_codegraph_contract.sh. Never edit those by hand.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-main}"
REPO="https://github.com/colbymchenry/codegraph"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "fetching $REPO @ $REF ..."
git clone -q --depth 1 --branch "$REF" "$REPO" "$TMP/cg" 2>/dev/null \
  || { git init -q "$TMP/cg" && git -C "$TMP/cg" remote add origin "$REPO" \
       && git -C "$TMP/cg" fetch -q --depth 1 origin "$REF" && git -C "$TMP/cg" checkout -q FETCH_HEAD; }
SHA="$(git -C "$TMP/cg" rev-parse --short HEAD)"
VER="$(grep -oE '"version": *"[^"]+"' "$TMP/cg/package.json" | head -1 | grep -oE '[0-9][^"]*')"
SCHEMA_VER="$(grep -oE 'CURRENT_SCHEMA_VERSION *= *[0-9]+' "$TMP/cg/src/db/migrations.ts" | grep -oE '[0-9]+$')"
[ -n "$SCHEMA_VER" ] || { echo "could not read CURRENT_SCHEMA_VERSION"; exit 1; }

cp "$TMP/cg/src/db/schema.sql" "$ROOT/ffi/codegraph/schema.sql"
cp "$TMP/cg/LICENSE" "$ROOT/ffi/codegraph/LICENSE.codegraph"
sed -i.bak -E "s/^(\| upstream commit \| )\`[^\`]*\`.*\|/\1\`$SHA\` (package version $VER) |/; s/^(\| \`CURRENT_SCHEMA_VERSION\` \| )[0-9]+/\1$SCHEMA_VER/" "$ROOT/ffi/codegraph/README.md"
sed -i.bak -E "s/^(CODEGRAPH_SCHEMA_VERSION +:: +)[0-9]+/\1$SCHEMA_VER/" "$ROOT/src/core/graph_schema.odin"
rm -f "$ROOT/ffi/codegraph/README.md.bak" "$ROOT/src/core/graph_schema.odin.bak"

echo "vendored CodeGraph $VER ($SHA), schema version $SCHEMA_VER"
git -C "$ROOT" --no-pager diff --stat -- ffi/codegraph src/core/graph_schema.odin || true
echo
echo "next: ./scripts/build.sh && CODEGRAPH_BIN=<codegraph at that version> ./scripts/test_codegraph_contract.sh"
