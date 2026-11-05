#!/usr/bin/env bash
# ci_suites.sh — run every rule suite plus the MCP and config tests; exit 1 if any fails.
# Used by .github/workflows/build.yml on macOS and Linux. Run from the repository root after scripts/build.sh.
# New scripts/run_*.sh suites are picked up automatically.
set -u

FAILED=0

for t in scripts/run_*.sh scripts/test_m9_config.sh; do
  echo "--- $t ---"
  bash "$t" || { echo "FAILED: $t"; FAILED=1; }
done

echo "--- scripts/test_m8_mcp.py ---"
python3 scripts/test_m8_mcp.py || { echo "FAILED: scripts/test_m8_mcp.py"; FAILED=1; }

# olt lints itself; both runs must say "No violations".
OLT="$(ls artifacts/*/olt | head -1)"
echo "--- olt lints its own source ---"
"$OLT" src/ | tail -1 | grep -q 'No violations' || { echo "FAILED: olt src/"; FAILED=1; }
"$OLT" src/ --rule C021,C022,C023 | tail -1 | grep -q 'No violations' || { echo "FAILED: olt src/ --rule C021,C022,C023"; FAILED=1; }

exit "$FAILED"
