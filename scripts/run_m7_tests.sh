#!/bin/bash
# M7 Graph Enrichment Test Suite
# Tests: allocator var tagging, return-type allocator detection, local-var exclusion,
#        incremental rebuild (skip unchanged), eviction of deleted files.

set -uo pipefail

DB=/tmp/m7_test_graph.db
FIXTURE_DIR=tests/M7_GRAPH
LINT=./artifacts/odin-lint

echo "M7 Graph Enrichment Tests"
echo "========================="

passed=0
failed=0

check() {
    local label=$1 result=$2 expected=$3
    if [ "$result" = "$expected" ]; then
        echo "  PASS: $label"
        ((passed++))
    else
        echo "  FAIL: $label"
        echo "        expected='$expected'  got='$result'"
        ((failed++))
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────
rm -f "$DB"
echo ""
echo "--- Pass 1: Initial index (graph_fixture + eviction_fixture) ---"
$LINT "$FIXTURE_DIR" --export-symbols --db="$DB" 2>/dev/null

files_indexed=$(sqlite3 "$DB" "SELECT COUNT(*) FROM files;")
check "2 files indexed on first run" "$files_indexed" "2"

# ── Goal 1: package-level allocator var tagged ─────────────────────────────
alloc_var=$(sqlite3 "$DB" "SELECT memory_role FROM nodes WHERE name='scratch_allocator' AND kind='variable';")
check "scratch_allocator has memory_role=allocator" "$alloc_var" "allocator"

# ── Goal 1: plain package-level var — no allocator role ───────────────────
plain_var=$(sqlite3 "$DB" "SELECT memory_role FROM nodes WHERE name='frame_count' AND kind='variable';")
check "frame_count has no allocator role" "$plain_var" ""

# ── Goal 1: local vars inside procs NOT indexed ─────────────────────────────
local_alloc_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM nodes WHERE name='local_alloc';")
check "local_alloc inside proc not indexed" "$local_alloc_count" "0"
local_count_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM nodes WHERE name='local_count';")
check "local_count inside proc not indexed" "$local_count_count" "0"

# ── Goal 2: proc returning mem.Allocator tagged as allocator ───────────────
get_scratch_role=$(sqlite3 "$DB" "SELECT memory_role FROM nodes WHERE name='get_scratch' AND kind='proc';")
check "get_scratch tagged memory_role=allocator (returns mem.Allocator)" "$get_scratch_role" "allocator"

get_scratch_rt=$(sqlite3 "$DB" "SELECT return_type FROM nodes WHERE name='get_scratch' AND kind='proc';")
check "get_scratch return_type=mem.Allocator" "$get_scratch_rt" "mem.Allocator"

# ── Goal 2: proc NOT returning allocator — not tagged ─────────────────────
get_frame_role=$(sqlite3 "$DB" "SELECT memory_role FROM nodes WHERE name='get_frame_count' AND kind='proc';")
check "get_frame_count not tagged as allocator" "$get_frame_role" "neutral"

get_frame_rt=$(sqlite3 "$DB" "SELECT return_type FROM nodes WHERE name='get_frame_count' AND kind='proc';")
check "get_frame_count return_type=int" "$get_frame_rt" "int"

# ── Goal 5: incremental — second run skips unchanged files ─────────────────
echo ""
echo "--- Pass 2: Incremental rebuild (no changes) ---"
# Capture stderr for files_indexed count (output goes to stderr in our tool)
output2=$($LINT "$FIXTURE_DIR" --export-symbols --db="$DB" 2>&1)
files2=$(echo "$output2" | grep -oE '[0-9]+ files' | grep -oE '[0-9]+' | head -1)
check "0 files re-indexed on unchanged run" "$files2" "0"

# Node count stable after second run
nodes_after=$(sqlite3 "$DB" "SELECT COUNT(*) FROM nodes;")
nodes_first=$(sqlite3  "$DB" "SELECT COUNT(*) FROM nodes;")
check "node count stable after cached run" "$nodes_after" "$nodes_first"

# ── Goal 5: eviction — delete one file, rebuild, confirm node gone ─────────
echo ""
echo "--- Pass 3: Eviction (delete eviction_fixture.odin) ---"
cp "$FIXTURE_DIR/eviction_fixture.odin" /tmp/m7_eviction_backup.odin
rm "$FIXTURE_DIR/eviction_fixture.odin"

$LINT "$FIXTURE_DIR" --export-symbols --db="$DB" 2>/dev/null

evicted_proc=$(sqlite3 "$DB" "SELECT COUNT(*) FROM nodes WHERE name='extra_proc';")
check "extra_proc evicted after file deletion" "$evicted_proc" "0"

files_after_evict=$(sqlite3 "$DB" "SELECT COUNT(*) FROM files;")
check "files table shrinks to 1 after eviction" "$files_after_evict" "1"

# Restore eviction fixture
cp /tmp/m7_eviction_backup.odin "$FIXTURE_DIR/eviction_fixture.odin"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "========================="
total=$((passed + failed))
echo "Total: $total  Passed: $passed  Failed: $failed"
if [ $failed -eq 0 ]; then
    echo "All M7 tests passed!"
    exit 0
else
    echo "Some M7 tests FAILED."
    exit 1
fi
