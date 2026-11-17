#!/usr/bin/env bash
# run_update_tests.sh — `olt update` against a fake GitHub API, a fake curl and throwaway archives.
# Never touches the network and never replaces a binary outside the work directory.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"          # sets OLT_BINARY and PLATFORM

case "$PLATFORM" in
  macos-arm64|linux-x86_64) ;;
  *) echo "skip: update tests only run on platforms that publish a release ($PLATFORM)"; exit 0 ;;
esac

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

LOCAL="$("$OLT_BINARY" --version | awk '/^olt /{print $2}')"
[ -n "$LOCAL" ] || { echo "cannot read the local version"; exit 2; }

# ── fake curl ────────────────────────────────────────────────────────────────
# The updater calls: curl -fsSL -H ... -H ... -o <file> <url>
mkdir -p "$WORK/stubs"
cat > "$WORK/stubs/curl" <<'SH'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  *api.github.com*) src="$FAKE_API" ;;
  *)                src="$FAKE_ASSET" ;;
esac
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
SH
chmod +x "$WORK/stubs/curl"

# make_release <version> <digest>  — asset archive + API response for one version
make_release() {
  local ver="$1" digest="$2" name="olt-$1-$PLATFORM"
  rm -rf "$WORK/stage"; mkdir -p "$WORK/stage/$name"
  printf '#!/bin/sh\necho fake-olt-%s\n' "$ver" > "$WORK/stage/$name/olt"
  chmod +x "$WORK/stage/$name/olt"
  tar -czf "$WORK/asset.tar.gz" -C "$WORK/stage" "$name"
  local real
  real="$(python3 - "$WORK/asset.tar.gz" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
  [ -z "$digest" ] && digest="sha256:$real"
  cat > "$WORK/release.json" <<EOF
{"tag_name":"v$ver","assets":[{"name":"$name.tar.gz","browser_download_url":"https://example.invalid/$name.tar.gz","digest":"$digest","size":$(wc -c < "$WORK/asset.tar.gz" | tr -d ' ')}]}
EOF
}

# run_update <binary> <args...>  — with the stubs first on PATH
run_update() {
  local bin="$1"; shift
  PATH="$WORK/stubs:$PATH" FAKE_API="$WORK/release.json" FAKE_ASSET="$WORK/asset.tar.gz" \
    "$bin" update "$@"
}

echo "== 1. help and argument handling"
run_update "$OLT_BINARY" --help | grep -q -- '--check' && ok "--help documents --check" || bad "--help documents --check"
rc=0; run_update "$OLT_BINARY" --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "an unknown argument exits 2" || bad "an unknown argument exits 2 (got $rc)"

echo "== 2. --check reporting and exit codes"
make_release "9.9.9" ""
rc=0; out="$(run_update "$OLT_BINARY" --check 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && ok "a newer release makes --check exit 1" || bad "a newer release makes --check exit 1 (got $rc)"
case "$out" in *"$LOCAL"*"9.9.9"*) ok "--check prints both versions" ;; *) bad "--check prints both versions: $out" ;; esac

make_release "$LOCAL" ""
rc=0; run_update "$OLT_BINARY" --check >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "the current release makes --check exit 0" || bad "the current release makes --check exit 0 (got $rc)"

make_release "0.0.1" ""
rc=0; out="$(run_update "$OLT_BINARY" --check 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && ok "an older release does not offer a downgrade" || bad "an older release does not offer a downgrade (got $rc)"
case "$out" in *"newer than the latest"*) ok "an older release says the installed build is newer" ;; *) bad "an older release says the installed build is newer: $out" ;; esac

echo "== 3. install over the running binary"
mkdir -p "$WORK/bin"; cp "$OLT_BINARY" "$WORK/bin/olt"
make_release "9.9.9" ""
rc=0; run_update "$WORK/bin/olt" >"$WORK/install.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "a newer release installs (exit 0)" || { bad "a newer release installs (got $rc)"; sed 's/^/       /' "$WORK/install.log"; }
[ "$("$WORK/bin/olt" 2>&1)" = "fake-olt-9.9.9" ] && ok "the running binary was replaced" || bad "the running binary was replaced"

echo "== 4. integrity and asset failures"
mkdir -p "$WORK/bin2"; cp "$OLT_BINARY" "$WORK/bin2/olt"
make_release "9.9.9" "sha256:0000000000000000000000000000000000000000000000000000000000000000"
rc=0; run_update "$WORK/bin2/olt" >"$WORK/mismatch.log" 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "a digest mismatch exits 2" || bad "a digest mismatch exits 2 (got $rc)"
grep -q 'SHA-256 mismatch' "$WORK/mismatch.log" && ok "a digest mismatch is named in the output" || bad "a digest mismatch is named in the output"
"$WORK/bin2/olt" --version >/dev/null 2>&1 && ok "a digest mismatch leaves the binary alone" || bad "a digest mismatch leaves the binary alone"

make_release "9.9.9" ""
python3 - "$WORK/release.json" <<'PY'
import json, sys
# Publish only another platform's asset, so the current one is missing.
path = sys.argv[1]
d = json.load(open(path))
d["assets"][0]["name"] = "olt-9.9.9-other-platform.tar.gz"
json.dump(d, open(path, "w"))
PY
rc=0; out="$(run_update "$OLT_BINARY" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] && ok "a release without this platform's asset exits 2" || bad "a release without this platform's asset exits 2 (got $rc)"
case "$out" in *"has no asset"*) ok "the missing asset is reported" ;; *) bad "the missing asset is reported: $out" ;; esac

echo "== 5. no digest published"
make_release "9.9.9" "null"
python3 - "$WORK/release.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d["assets"][0]["digest"]
json.dump(d, open(sys.argv[1], "w"))
PY
mkdir -p "$WORK/bin3"; cp "$OLT_BINARY" "$WORK/bin3/olt"
rc=0; out="$(run_update "$WORK/bin3/olt" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && ok "a missing digest still installs" || bad "a missing digest still installs (got $rc)"
case "$out" in *"no SHA-256 digest"*) ok "a missing digest warns" ;; *) bad "a missing digest warns" ;; esac

echo ""
echo "Update: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
