🎯 Comprehensive Migration TODO List

📋 Phase 1: Pre-Migration Cleanup (Mandatory Before Starting)
TODO 1.1: Delete Obsolete Files
rm src/core/c002-COR-Pointer.odin.backup
rm src/core/c002-COR-Pointer.odin.improved.re
rm src/core/c002-COR-Pointer.odin.old
rm src/core/main.odin.backup
rm src/core/main.odin.backup2
rm src/core/odin_lint_plugin.odin

Verification:
ls src/core/*.backup 2>/dev/null | wc -l  # Should output: 0
grep -l "get_odin_lint_plugin" src/core/ | wc -l  # Should output: 1

TODO 1.2: Create queries Directory

mkdir -p ffi/tree_sitter/queries
Verification:
ls -la ffi/tree_sitter/queries/  # Should show empty directory

TODO 1.3: Verify Build Still Works
./scripts/build.sh

Verification:
test -f artifacts/odin-lint && echo "Build OK" || echo "Build FAILED"

GATE 1: Pre-Migration Cleanup
•  
✅ No backup files exist
•  ✅ Only one plugin file exists
•  ✅ Build succeeds
•  ✅ C001 tests pass
•  ✅ C002 tests pass
•  ✅ queries directory exists

📋 Phase 2: SCM Query Engine Implementation (M3.1)
TODO 2.1: Add Query API Bindings to tree_sitter_bindings.odin

•  Add 7 query functions to existing foreign ts block
•  Add TSQueryError, TSQueryCapture, TSQueryMatch structs
Verification:

grep -c "ts_query_new" src/core/tree_sitter_bindings.odin  # Should output: 1
grep -c "TSQueryError" src/core/tree_sitter_bindings.odin  # Should output: 1

TODO 2.2: Create query_engine.odin

•  Implement load_query, unload_query, run_query
•  Add QueryResult and CompiledQuery structs
Verification:
test -f src/core/query_engine.odin && echo "File exists" || echo "File missing"
grep -c "load_query" src/core/query_engine.odin  # Should output: 1

TODO 2.3: Create memory_safety.scm

cat > ffi/tree_sitter/queries/memory_safety.scm << 'EOF'
; memory_safety.scm
; Captures for C001 (memory allocation without defer free)
; and C002 (double-free via defer).

(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @alloc_fn
      (#match? @alloc_fn "^(make|new)$")))) @alloc

(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var))) @defer_free
EOF
Verification:

test -f ffi/tree_sitter/queries/memory_safety.scm && echo "SCM file exists"
TODO 2.4: Test Query Engine Compilation
./scripts/build.sh

Verification:
test $? -eq 0 && echo "Build successful" || echo "Build failed"

GATE 2: Query Engine Implementation
•  ✅ Query API bindings added
•  ✅ query_engine.odin created and compiles
•  ✅ memory_safety.scm created
•  ✅ Build succeeds without errors
•  ✅ C001/C002 functionality unchanged

 Phase 3: C002 SCM Migration (M3.2)

TODO 3.1: Add c002_scm_matcher to c002-COR-Pointer.odin

•  Implement SCM-based double-free detection
•  Use query results instead of manual AST walking
Verification:

grep -c "c002_scm_matcher" src/core/c002-COR-Pointer.odin  # Should output: 1
TODO 3.2: Enable Shadow Mode in main.odin
•  
Add shadow comparison code with when ODIN_DEBUG
•  Compare manual vs SCM results
Verification:
grep -c "c002_scm_matcher" src/core/main.odin  # Should output: 1

TODO 3.3: Build Debug Version and Test Parity
odin build src/core -out:artifacts/odin-lint-debug -debug \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a"

Verification:

./scripts/run_c002_tests.sh 2>&1 | grep "\[shadow\]" | wc -l  # Should output: 0
TODO 3.4: Retire Manual Walker (After Parity Confirmed)

•  Remove manual c002Matcher call from main.odin
•  Mark old function as deprecated
Verification:
./scripts/run_c002_tests.sh  # Should produce same results as before

GATE 3: C002 SCM Migration

•  ✅ c002_scm_matcher implemented
•  ✅ Shadow mode shows zero parity failures
•  ✅ Manual walker retired
•  ✅ All C002 tests pass
•  ✅ No regressions in other rules

📋 Phase 4: C003-C008 Real Implementation (M3.3)

TODO 4.1: Create naming_rules.scm
cat > ffi/tree_sitter/queries/naming_rules.scm << 'EOF'
; naming_rules.scm
; Captures for C003 (proc names), C004 (private visibility),
; C006 (public doc comments), C007 (type names), C008 (acronyms).

(procedure_declaration
  name: (identifier) @proc_name)

(type_declaration
  name: (identifier) @type_name)

(comment) @doc_comment
EOF

Verification:
test -f ffi/tree_sitter/queries/naming_rules.scm

TODO 4.2: Implement C003 (snake_case procs)
•  
Replace stub with real implementation
•  Add is_snake_case helper function
Verification:
grep -c "is_snake_case" src/core/c003-STY-Naming.odin  # Should output: 1

TODO 4.3: Implement C004-C008
•  
Follow same pattern as C003
•  Each rule ~30-50 lines
Verification:

for rule in c004 c005 c006 c007 c008; do
    grep -c "Matcher" src/core/${rule}-STY-*.odin
done
TODO 4.4: Wire Rules into main.odin

•  Load naming query once at startup
•  Pass to all C003-C008 matchers
Verification:

grep -c "naming_query" src/core/main.odin  # Should output: >= 1
GATE 4: C003-C008 Implementation

•  ✅ naming_rules.scm created
•  ✅ All 6 rules implemented
•  ✅ Each rule has 3+ test fixtures
•  ✅ No regressions in C001/C002
•  ✅ Build succeeds

📋 Phase 5: Odin 2026 Migration Rules (M3.4)

TODO 5.1: Create odin2026_migration.scm

cat > ffi/tree_sitter/queries/odin2026_migration.scm << 'EOF'
; odin2026_migration.scm
; Detects usage of deprecated Odin APIs that will break in Q3 2026.

(import_declaration
  path: (interpreted_string_literal) @import_path
  (#match? @import_path "\"core:os/old\"")) @legacy_os_import

(call_expression
  function: (selector_expression
    field: (field_identifier) @fn_name
    (#eq? @fn_name "Small_Array"))) @small_array_call
EOF
Verification:

test -f ffi/tree_sitter/queries/odin2026_migration.scm
TODO 5.2: Implement C009 (Legacy OS)

•  Create c009-MIG-LegacyOS.odin
•  Flag core:os/old imports only
Verification:
test -f src/core/c009-MIG-LegacyOS.odin

TODO 5.3: Implement C010 (SmallArray)
•  
Create c010-MIG-SmallArray.odin
•  Flag Small_Array usage
Verification:

test -f src/core/c010-MIG-SmallArray.odin
GATE 5: Odin 2026 Rules

•  ✅ odin2026_migration.scm created
•  ✅ C009 implemented and tested
•  ✅ C010 implemented and tested
•  ✅ C009 silent on core:os (critical!)
•  ✅ All prior tests pass

📋 Phase 6: CLI Enhancements (M4)

TODO 6.1: Create config.odin

•  Implement TOML parsing
•  Add Config and RuleConfig structs
Verification:

test -f src/core/config.odin
TODO 6.2: Add CLI Flag Parsing

•  Replace current arg parsing
•  Add --help, --list-rules, --rule, --format
Verification:
./artifacts/odin-lint --help | grep "Usage:" | wc -l  # Should output: 1

TODO 6.3: Implement JSON Output
•  
Add --format json support
•  Output valid JSON diagnostics
Verification:
./artifacts/odin-lint test.odin --format json | jq . > /dev/null && echo "Valid JSON"

GATE 6: CLI Enhancements
•  
✅ --help works
•  ✅ --list-rules works
•  ✅ --rule filter works
•  ✅ --format json valid
•  ✅ No regressions

📋 Phase 7: Autofix Layer (M4.5)

TODO 7.1: Create autofix.odin
•  
Implement FixEdit struct
•  Add apply_fix and apply_fixes functions
Verification:
test -f src/core/autofix.odin

TODO 7.2: Implement C001 Autofix
•  
Add fix_for_c001 function
•  Add --fix and --fix-dry-run flags
Verification:

./artifacts/odin-lint c001_fail.odin --fix-dry-run | grep "defer free" | wc -l  # Should output: >= 1
GATE 7: Autofix Layer
•  
✅ --fix-dry-run shows edits
•  ✅ --fix applies correctly
•  ✅ Re-lint shows 0 violations
•  ✅ Idempotent (second --fix does nothing)

📋 Phase 8: OLS Plugin (M5)

TODO 8.1: Implement odin_lint_analyze_file

•  Replace stub with real implementation
•  Add OLS AST processing
Verification:

grep -c "odin_lint_analyze_file" src/core/plugin_main.odin  # Should output: 1
GATE 8: OLS Plugin

•  ✅ Plugin builds
•  ✅ C001 diagnostic appears in editor
•  ✅ Quick fix offered

📋 Phase 9: MCP Gateway (M5.5)

TODO 9.1: Create src/mcp/ Package

mkdir -p src/mcp
TODO 9.2: Implement mcp_server.odin

•  Streamable HTTP server on :6789
•  JSON-RPC 2.0 protocol
TODO 9.3: Create server_card.json
cat > src/mcp/server_card.json << 'EOF'
{
  "schema": "mcp-server-card/1.0",
  "name": "odin-lint",
  "version": "7.1.0",
  "description": "Semantic linting and code intelligence for the Odin programming language",
  "tools": [
    {
      "name": "run_lint_denoise",
      "description": "Run odin-lint on a code snippet and return structured violations for AI to fix",
      "parameters": {
        "code": "string — Odin source code to lint",
        "rules": "string (optional) — comma-separated rule IDs to check"
      }
    },
    {
      "name": "get_dna_context",
      "description": "Get semantic context for a procedure: callers, callees, memory role",
      "parameters": {
        "proc_name": "string — procedure name to look up"
      }
    }
  ],
  "transport": "streamable-http",
  "endpoint": "http://localhost:6789/mcp"
}

GATE 9: MCP Gateway


•  ✅ Server starts on :6789
•  ✅ Server card accessible
•  ✅ run_lint_denoise works
•  ✅ Connected to MCP client

📋 Phase 10: DNA Impact Analysis (M5.6)

TODO 10.1: Create dna_exporter.odin

•  Implement SymbolExport and DNAExport structs
•  Add classify_memory_role function
TODO 10.2: Implement --export-symbols

•  Generate symbols.json
•  Populate callers, callees, memory_role
GATE 10: DNA Impact Analysis
•  
✅ symbols.json generated
•  ✅ Callers/callees populated
•  ✅ Memory roles correct
•  ✅ MCP tools work

🎯 Master Verification Checklist
After Each Phase:

 1.  ✅ Build succeeds (./scripts/build.sh)
 2.  ✅ All existing tests pass
 3.  ✅ New functionality works as specified
 4.  ✅ No regressions introduced
 5.  ✅ Git commit created with clear message
Final Verification:
•  
✅ All 10 phases completed
•  ✅ All gates passed
•  ✅ Comprehensive test suite passes
•  ✅ Documentation updated
•  ✅ Production-ready deployment
This structured approach ensures careful, perfect execution of the V7 migration plan with verification at every step!