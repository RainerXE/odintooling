# odintooling — Migration to V7 TODO List
*Structured Execution Plan with Verification Steps and Git Safepoints*
*Created: April 2026 · Companion to odintooling-migration-toV7plan.md*

---

## 📋 Execution Instructions

1. **Work in Order**: Complete phases sequentially. Do not skip ahead.
2. **Verify Each Step**: Run the verification commands after each TODO.
3. **Git Safepoint**: Create a commit after each phase with format:
   `git commit -m "MIGRATION: Phase X - [brief description]"`
4. **Gate Checks**: All checks in a gate must pass before proceeding.
5. **On Failure**: Fix the issue immediately. Do not accumulate debt.

---

## 🎯 Phase 1: Pre-Migration Cleanup

### TODO 1.1: Delete Obsolete Files
```bash
rm src/core/c002-COR-Pointer.odin.backup
rm src/core/c002-COR-Pointer.odin.improved.re
rm src/core/c002-COR-Pointer.odin.old
rm src/core/main.odin.backup
rm src/core/main.odin.backup2
rm src/core/odin_lint_plugin.odin
```

**Verification:**
```bash
ls src/core/*.backup 2>/dev/null | wc -l  # Expected: 0
grep -l "get_odin_lint_plugin" src/core/ | wc -l  # Expected: 1
```

### TODO 1.2: Create queries Directory
```bash
mkdir -p ffi/tree_sitter/queries
```

**Verification:**
```bash
ls -la ffi/tree_sitter/queries/  # Expected: empty directory
```

### TODO 1.3: Verify Build Still Works
```bash
./scripts/build.sh
```

**Verification:**
```bash
test -f artifacts/odin-lint && echo "Build OK" || echo "Build FAILED"
```

### GATE 1: Pre-Migration Cleanup
- [ ] No backup files exist
- [ ] Only one plugin file exists
- [ ] Build succeeds
- [ ] C001 tests pass
- [ ] C002 tests pass
- [ ] queries directory exists

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 1 - Pre-migration cleanup completed"
```

---

## 🎯 Phase 2: SCM Query Engine Implementation (M3.1)

### TODO 2.1: Add Query API Bindings
Edit `src/core/tree_sitter_bindings.odin`:
- Add 7 query functions to existing `foreign ts` block
- Add `TSQueryError`, `TSQueryCapture`, `TSQueryMatch` structs

**Verification:**
```bash
grep -c "ts_query_new" src/core/tree_sitter_bindings.odin  # Expected: 1
grep -c "TSQueryError" src/core/tree_sitter_bindings.odin  # Expected: 1
```

### TODO 2.2: Create query_engine.odin
Create `src/core/query_engine.odin` with:
- `QueryResult` and `CompiledQuery` structs
- `load_query`, `unload_query`, `run_query` functions
- `free_query_results` helper

**Verification:**
```bash
test -f src/core/query_engine.odin && echo "File exists" || echo "File missing"
grep -c "load_query" src/core/query_engine.odin  # Expected: 1
```

### TODO 2.3: Create memory_safety.scm
```bash
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
```

**Verification:**
```bash
test -f ffi/tree_sitter/queries/memory_safety.scm && echo "SCM file exists"
```

### TODO 2.4: Test Query Engine Compilation
```bash
./scripts/build.sh
```

**Verification:**
```bash
test $? -eq 0 && echo "Build successful" || echo "Build failed"
```

### GATE 2: Query Engine Implementation
- [ ] Query API bindings added
- [ ] query_engine.odin created and compiles
- [ ] memory_safety.scm created
- [ ] Build succeeds without errors
- [ ] C001/C002 functionality unchanged

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 2 - SCM Query Engine implemented"
```

---

## 🎯 Phase 3: C002 SCM Migration (M3.2)

### TODO 3.1: Add c002_scm_matcher
Edit `src/core/c002-COR-Pointer.odin`:
- Add `c002_scm_matcher` function at bottom
- Use query results instead of manual AST walking

**Verification:**
```bash
grep -c "c002_scm_matcher" src/core/c002-COR-Pointer.odin  # Expected: 1
```

### TODO 3.2: Enable Shadow Mode
Edit `src/core/main.odin`:
- Add shadow comparison code with `when ODIN_DEBUG`
- Compare manual vs SCM results

**Verification:**
```bash
grep -c "c002_scm_matcher" src/core/main.odin  # Expected: 1
```

### TODO 3.3: Build Debug Version and Test Parity
```bash
odin build src/core -out:artifacts/odin-lint-debug -debug \
    -extra-linker-flags:"ffi/tree_sitter/tree-sitter-lib/libtree-sitter.a \
    ffi/tree_sitter/tree-sitter-odin/libtree-sitter-odin.a"
```

**Verification:**
```bash
./scripts/run_c002_tests.sh 2>&1 | grep "\[shadow\]" | wc -l  # Expected: 0
```

### TODO 3.4: Retire Manual Walker
Edit `src/core/main.odin` and `src/core/c002-COR-Pointer.odin`:
- Remove manual `c002Matcher` call
- Mark old function as deprecated

**Verification:**
```bash
./scripts/run_c002_tests.sh  # Should produce same results as before
```

### GATE 3: C002 SCM Migration
- [ ] c002_scm_matcher implemented
- [ ] Shadow mode shows zero parity failures
- [ ] Manual walker retired
- [ ] All C002 tests pass
- [ ] No regressions in other rules

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 3 - C002 SCM migration completed"
```

---

## 🎯 Phase 4: C003-C008 Real Implementation (M3.3)

### TODO 4.1: Create naming_rules.scm
```bash
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
```

**Verification:**
```bash
test -f ffi/tree_sitter/queries/naming_rules.scm
```

### TODO 4.2: Implement C003 (snake_case procs)
Edit `src/core/c003-STY-Naming.odin`:
- Replace stub with real implementation
- Add `is_snake_case` helper function

**Verification:**
```bash
grep -c "is_snake_case" src/core/c003-STY-Naming.odin  # Expected: 1
```

### TODO 4.3: Implement C004-C008
For each rule (c004-c008):
- Follow same pattern as C003
- Each rule ~30-50 lines
- Use naming query results

**Verification:**
```bash
for rule in c004 c005 c006 c007 c008; do
    grep -c "Matcher" src/core/${rule}-STY-*.odin
done
```

### TODO 4.4: Wire Rules into main.odin
Edit `src/core/main.odin`:
- Load naming query once at startup
- Pass to all C003-C008 matchers

**Verification:**
```bash
grep -c "naming_query" src/core/main.odin  # Expected: >= 1
```

### GATE 4: C003-C008 Implementation
- [ ] naming_rules.scm created
- [ ] All 6 rules implemented
- [ ] Each rule has 3+ test fixtures
- [ ] No regressions in C001/C002
- [ ] Build succeeds

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 4 - C003-C008 naming rules implemented"
```

---

## 🎯 Phase 5: Odin 2026 Migration Rules (M3.4)

### TODO 5.1: Create odin2026_migration.scm
```bash
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
```

**Verification:**
```bash
test -f ffi/tree_sitter/queries/odin2026_migration.scm
```

### TODO 5.2: Implement C009 (Legacy OS)
Create `src/core/c009-MIG-LegacyOS.odin`:
- Flag `core:os/old` imports only
- Do NOT flag `core:os` (critical!)

**Verification:**
```bash
test -f src/core/c009-MIG-LegacyOS.odin
```

### TODO 5.3: Implement C010 (SmallArray)
Create `src/core/c010-MIG-SmallArray.odin`:
- Flag Small_Array usage
- Suggest `[dynamic; N]T` syntax

**Verification:**
```bash
test -f src/core/c010-MIG-SmallArray.odin
```

### GATE 5: Odin 2026 Rules
- [ ] odin2026_migration.scm created
- [ ] C009 implemented and tested
- [ ] C010 implemented and tested
- [ ] C009 silent on `core:os` (critical!)
- [ ] All prior tests pass

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 5 - Odin 2026 migration rules implemented"
```

---

## 🎯 Phase 6: CLI Enhancements (M4)

### TODO 6.1: Create config.odin
Create `src/core/config.odin`:
- Implement TOML parsing
- Add Config and RuleConfig structs

**Verification:**
```bash
test -f src/core/config.odin
```

### TODO 6.2: Add CLI Flag Parsing
Edit `src/core/main.odin`:
- Replace current arg parsing
- Add --help, --list-rules, --rule, --format

**Verification:**
```bash
./artifacts/odin-lint --help | grep "Usage:" | wc -l  # Expected: 1
```

### TODO 6.3: Implement JSON Output
Edit `src/core/main.odin`:
- Add --format json support
- Output valid JSON diagnostics

**Verification:**
```bash
./artifacts/odin-lint test.odin --format json | jq . > /dev/null && echo "Valid JSON"
```

### GATE 6: CLI Enhancements
- [ ] --help works
- [ ] --list-rules works
- [ ] --rule filter works
- [ ] --format json valid
- [ ] No regressions

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 6 - CLI enhancements completed"
```

---

## 🎯 Phase 7: Autofix Layer (M4.5)

### TODO 7.1: Create autofix.odin
Create `src/core/autofix.odin`:
- Implement FixEdit struct
- Add apply_fix and apply_fixes functions

**Verification:**
```bash
test -f src/core/autofix.odin
```

### TODO 7.2: Implement C001 Autofix
Edit `src/core/c001-COR-Memory.odin`:
- Add fix_for_c001 function
- Add --fix and --fix-dry-run flags to main.odin

**Verification:**
```bash
./artifacts/odin-lint c001_fail.odin --fix-dry-run | grep "defer free" | wc -l  # Expected: >= 1
```

### GATE 7: Autofix Layer
- [ ] --fix-dry-run shows edits
- [ ] --fix applies correctly
- [ ] Re-lint shows 0 violations
- [ ] Idempotent (second --fix does nothing)

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 7 - Autofix layer implemented"
```

---

## 🎯 Phase 8: OLS Plugin (M5)

### TODO 8.1: Implement odin_lint_analyze_file
Edit `src/core/plugin_main.odin`:
- Replace stub with real implementation
- Add OLS AST processing

**Verification:**
```bash
grep -c "odin_lint_analyze_file" src/core/plugin_main.odin  # Expected: 1
```

### GATE 8: OLS Plugin
- [ ] Plugin builds
- [ ] C001 diagnostic appears in editor
- [ ] Quick fix offered

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 8 - OLS plugin completed"
```

---

## 🎯 Phase 9: MCP Gateway (M5.5)

### TODO 9.1: Create src/mcp/ Package
```bash
mkdir -p src/mcp
```

### TODO 9.2: Implement mcp_server.odin
Create `src/mcp/mcp_server.odin`:
- Streamable HTTP server on :6789
- JSON-RPC 2.0 protocol

### TODO 9.3: Create server_card.json
```bash
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
EOF
```

### GATE 9: MCP Gateway
- [ ] Server starts on :6789
- [ ] Server card accessible
- [ ] run_lint_denoise works
- [ ] Connected to MCP client

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 9 - MCP gateway implemented"
```

---

## 🎯 Phase 10: DNA Impact Analysis (M5.6)

### TODO 10.1: Create dna_exporter.odin
Create `src/core/dna_exporter.odin`:
- Implement SymbolExport and DNAExport structs
- Add classify_memory_role function

### TODO 10.2: Implement --export-symbols
Edit `src/core/main.odin`:
- Add --export-symbols flag
- Generate symbols.json

### GATE 10: DNA Impact Analysis
- [ ] symbols.json generated
- [ ] Callers/callees populated
- [ ] Memory roles correct
- [ ] MCP tools work

**Git Safepoint:**
```bash
git add -A
git commit -m "MIGRATION: Phase 10 - DNA impact analysis completed"
```

---

## 🏁 Final Verification

### Master Checklist
- [ ] All 10 phases completed
- [ ] All gates passed
- [ ] Comprehensive test suite passes
- [ ] Documentation updated
- [ ] Production-ready deployment

### Final Git Safepoint
```bash
git add -A
git commit -m "MIGRATION: V7 migration completed - all phases passed"
```

---

*Version: 1.0*
*Created: April 2026*
*Companion documents:*
- `plans/odin-lint-implementation-planV7.md` (master plan)
- `plans/odintooling-migration-toV7plan.md` (detailed migration steps)
- `claude.md` (codebase setup reference)