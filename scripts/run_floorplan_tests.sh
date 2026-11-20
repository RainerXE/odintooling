#!/usr/bin/env bash
# run_floorplan_tests.sh — `olt floorplan`: HTML shell, embedded graph data,
# exact JSON mode, default paths, stale handling and error paths.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"

WORK="$(mktemp -d)"; WORK="$(cd "$WORK" && pwd -P)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

PROJ="$WORK/proj"
DB="$PROJ/.codegraph/olt.db"
mkdir -p "$PROJ/alpha" "$PROJ/beta"

cat > "$PROJ/alpha/a.odin" <<'ODIN'
package alpha

import "../beta"

foreign import c "bridge.c"

foreign {
	c_bridge :: proc(x: i32) -> i32 ---
}

foo :: proc(x: int) -> int {
	return x + 1
}

bar :: proc() -> int {
	return foo(1) + beta.baz()
}

Thing :: struct {
	value: int
}

leaky :: proc() {
	xs := make([]u8, 10)
	xs[0] = 1
}
ODIN

cat > "$PROJ/beta/b.odin" <<'ODIN'
package beta

baz :: proc() -> int {
	return 2
}
ODIN

cat > "$PROJ/alpha/bridge.c" <<'EOF'
int c_bridge(int x) { return x + 1; }
EOF

if "$OLT_BINARY" "$PROJ" --export-symbols --db "$DB" >"$WORK/export.log" 2>&1; then
  ok "export builds the fixture graph"
else
  bad "export builds the fixture graph"
  cat "$WORK/export.log"
  echo "floorplan tests: $PASS passed, $FAIL failed"
  exit 1
fi

# ── default database and default output ─────────────────────────────────────
if (cd "$PROJ" && "$OLT_BINARY" floorplan >"$WORK/default.log" 2>&1); then
  ok "floorplan finds .codegraph/olt.db and writes the default file"
else
  bad "floorplan finds .codegraph/olt.db and writes the default file"
  cat "$WORK/default.log"
fi
check "default output is .codegraph/floorplan.html" '[ -s "$PROJ/.codegraph/floorplan.html" ]'
check "floorplan prints the output path" 'grep -q "floorplan: wrote" "$WORK/default.log"'

# ── HTML and embedded data ──────────────────────────────────────────────────
"$OLT_BINARY" floorplan --db "$DB" --out "$WORK/map.html" --title "Fixture Map" >"$WORK/fp.log" 2>"$WORK/fp.err"
check "HTML output exists" '[ -s "$WORK/map.html" ]'
check "title is escaped into the HTML shell" 'grep -q "<title>Fixture Map</title>" "$WORK/map.html"'
check "HTML embeds the data script" 'grep -q "id=\"olt-floorplan-data\"" "$WORK/map.html"'
check "HTML includes the stylesheet" 'grep -q "\.room" "$WORK/map.html"'
check "HTML includes the app script" 'grep -q "olt floorplan — a self-contained" "$WORK/map.html"'
check "output is self-contained (no CDN)" '! grep -Eq "https?://(cdn|unpkg|jsdelivr|fonts\\.googleapis)" "$WORK/map.html"'

python3 - "$WORK/map.html" <<'PY'
import json, re, sys

html = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'<script id="olt-floorplan-data" type="application/json">(.*?)</script>', html, re.S)
assert match, "embedded data script is missing"
raw = match.group(1)
assert "</script>" not in raw, "embedded data contains a raw closing script tag"
data = json.loads(raw)

assert data["schema_version"] == 1, data.get("schema_version")
assert data["project"]["name"] == "Fixture Map", data["project"]
assert data["project"]["stale_file"] == "", data["project"]
assert data["summary"]["files"] == 2, data["summary"]
assert data["summary"]["packages"] == 2, data["summary"]
assert data["summary"]["symbols"] == 8, data["summary"]
assert data["summary"]["edges"] >= 8, data["summary"]
assert data["summary"]["unresolved"] <= 1, data["summary"]
assert data["summary"]["findings"] == 6, data["summary"]

packages = {(p["dir"], p["name"]) for p in data["packages"]}
assert packages == {("alpha", "alpha"), ("beta", "beta")}, packages

files = {f["path"]: f for f in data["files"]}
assert set(files) == {"alpha/a.odin", "beta/b.odin"}, files
assert files["alpha/a.odin"]["package"] == "alpha", files["alpha/a.odin"]
assert files["beta/b.odin"]["package"] == "beta", files["beta/b.odin"]

imports = {(i["file"], i["path"], i["dir"], i["internal"]) for i in data["imports"]}
assert ("alpha/a.odin", "../beta", "beta", True) in imports, imports
assert ("alpha/a.odin", "bridge.c", "alpha/bridge.c", False) in imports, imports

nodes = {n["name"]: n for n in data["nodes"] if n["kind"] != "file"}
assert "c_bridge" in nodes, nodes
assert "foo" in nodes and "bar" in nodes and "baz" in nodes, nodes
assert "C001" in nodes["leaky"]["lint"], nodes["leaky"]["lint"]
assert any(e["kind"] == "calls" for e in data["edges"]), "no call edges"

print("  ✅ PASS: embedded JSON has packages, files, imports, FFI and call edges")
PY
if [ $? -ne 0 ]; then bad "embedded JSON schema and contents"; fi

# ── --json mode ─────────────────────────────────────────────────────────────
"$OLT_BINARY" floorplan --db "$DB" --json >"$WORK/map.json" 2>"$WORK/json.err"
check "--json writes valid JSON to stdout" 'python3 -c "import json; d=json.load(open(\"$WORK/map.json\")); assert d[\"schema_version\"]==1; assert d[\"summary\"][\"files\"]==2"'
check "--json does not write an HTML file" '! grep -q "<!doctype html>" "$WORK/map.json"'

# ── nesting, escaping, errors, stale ────────────────────────────────────────
"$OLT_BINARY" floorplan --db "$DB" --out "$WORK/deep/a/b/map.html" >/dev/null 2>"$WORK/deep.err"
check "--out creates missing parent directories" '[ -s "$WORK/deep/a/b/map.html" ]'

"$OLT_BINARY" floorplan --db "$DB" --out "$WORK/escaped.html" --title '<script>alert(1)</script>' >/dev/null 2>&1
check "title is HTML-escaped" 'grep -q "<title>&lt;script&gt;alert(1)&lt;/script&gt;</title>" "$WORK/escaped.html"'

"$OLT_BINARY" floorplan --help >"$WORK/help" 2>&1
check "--help prints usage" 'grep -q "Usage: olt floorplan" "$WORK/help"'
check "--help explains the export prerequisite" 'grep -q "export-symbols" "$WORK/help"'

"$OLT_BINARY" floorplan --bogus >/dev/null 2>"$WORK/bogus.err"; rc=$?
check "unknown flag exits 2" '[ "$rc" -eq 2 ]'
check "unknown flag explains the problem" 'grep -q "unknown flag" "$WORK/bogus.err"'

"$OLT_BINARY" floorplan --db "$WORK/missing.db" >/dev/null 2>"$WORK/missing.err"; rc=$?
check "missing graph exits 2" '[ "$rc" -eq 2 ]'
check "missing graph suggests an export" 'grep -q "export-symbols" "$WORK/missing.err"'

touch -t 203001010000 "$PROJ/alpha/a.odin"
"$OLT_BINARY" floorplan --db "$DB" --json >"$WORK/stale.json" 2>"$WORK/stale.err"
check "changed source prints a stale note" 'grep -q "changed after the graph was built" "$WORK/stale.err"'
check "stale JSON identifies the changed file" 'python3 -c "import json; d=json.load(open(\"$WORK/stale.json\")); assert d[\"project\"][\"stale_file\"].endswith(\"alpha/a.odin\"), d[\"project\"]"'

# ── root package (dir "") stays an internal package ─────────────────────────
ROOTPROJ="$WORK/rootproj"
mkdir -p "$ROOTPROJ/sub"
cat > "$ROOTPROJ/main.odin" <<'ODIN'
package root

import "sub"

main :: proc() {
	sub.foo()
}
ODIN
cat > "$ROOTPROJ/sub/sub.odin" <<'ODIN'
package sub

foo :: proc() {}
ODIN
"$OLT_BINARY" "$ROOTPROJ" --export-symbols --db "$ROOTPROJ/.codegraph/olt.db" >/dev/null 2>&1
(cd "$ROOTPROJ" && "$OLT_BINARY" floorplan --json) >"$WORK/root.json" 2>"$WORK/root.err"
check "root package map data is valid" 'python3 -c "import json; d=json.load(open(\"$WORK/root.json\")); assert any(p[\"dir\"]==\"\" and p[\"name\"]==\"root\" for p in d[\"packages\"]), d[\"packages\"]"'
check "root package import is marked internal" 'python3 -c "import json; d=json.load(open(\"$WORK/root.json\")); assert any(i[\"path\"]==\"sub\" and i[\"internal\"] and i[\"dir\"]==\"sub\" for i in d[\"imports\"]), d[\"imports\"]"'

echo "floorplan tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
