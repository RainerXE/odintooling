# odin-lint Stabilization Review Report
*April 25 2026 — full codebase audit: memory safety, error handling, thread safety*

---

## Summary

| Severity | Count | Fixed (April 25 2026) |
|----------|-------|----------------------|
| HIGH     | 4     | ✅ All 4 fixed        |
| MEDIUM   | 7     | ✅ All 7 fixed        |
| LOW      | 4     | ✅ L1, L3 (was already safe), L4 fixed; L2 resolved by H4 |

The codebase has good defensive structure — nil checks are consistent, defer
is used correctly in most places, and the graph DB open/close pattern is
correctly scoped. The main systemic weakness is **suppression map cleanup**
(missing `delete` in every rule that calls `collect_suppressions`) and two
**LSP proxy leaks** in the newly added diagnostic injection code.

---

## HIGH SEVERITY

---

### H1 — `_free_nodes` omits `delete(n.return_type)`
**File:** `src/mcp/tool_graph.odin:660–663`

`_free_node` (singular, line 654) correctly deletes all 7 string fields
including `return_type`. `_free_nodes` (plural, line 660) was never updated
to match — it deletes 6 fields but not `return_type`.

Every batch graph query leaks one `return_type` string per node: callers,
callees, impact radius, allocators, search results. In a long-running MCP
server session this accumulates continuously.

```odin
// CURRENT — missing return_type
_free_nodes :: proc(nodes: []core.GraphNodeInfo) {
    for n in nodes {
        delete(n.name); delete(n.kind); delete(n.file)
        delete(n.memory_role); delete(n.lint_violations); delete(n.signature)
        // ← delete(n.return_type) MISSING
    }
}
```

**Fix:** Add `delete(n.return_type)` to match `_free_node`.

---

### H2 — Suppression maps never deleted (6 files)
**Files:**
- `src/core/c001-COR-Memory.odin:218`
- `src/core/c011-FFI-Safety.odin:103`
- `src/core/c019-STY-TypeMarker.odin:128`
- `src/core/c101-CTX-Integrity.odin:169`
- `src/core/c201-COR-UncheckedResult.odin:44`
- `src/core/c202-COR-SwitchExhaust.odin:44`
- `src/core/c203-COR-DeferScope.odin:41`

`collect_suppressions()` returns `map[int][]string` (heap-allocated). None of
the callers delete the returned map. Every file analyzed leaks one map per
rule that calls `collect_suppressions`. On a 1000-file project with 7 affected
rules enabled, that is 7000 leaked maps.

```odin
// CURRENT — no cleanup
suppressions := collect_suppressions(1, len(file_lines), file_lines)
// ... used in loop ...
return diagnostics[:]
// ← map never deleted
```

**Fix:** Add immediately after each `collect_suppressions` call:
```odin
suppressions := collect_suppressions(1, len(file_lines), file_lines)
defer delete(suppressions)
```
Note: the inner `[]string` slices are owned by the map values and do not
need separate deletion (they point into static suppression parse results).
Only the outer map itself needs to be deleted.

---

### H3 — LSP proxy Thread B leaks diagnostic strings on every event
**File:** `src/lsp/diagnostic_inject.odin:31, 94` and `src/lsp/proxy.odin:118–119`

`diags_to_lsp_items` and `merge_publish_diagnostics` both call
`strings.builder_make()` without `defer strings.builder_destroy(&sb)`, then
return `strings.to_string(sb)`. This returns a reference into the builder's
backing buffer without freeing the builder metadata. The backing buffer is
then unreachable and cannot be freed.

Additionally, the caller in `proxy.odin` (`_handle_publish_diagnostics`) never
deletes either the `our_items` or `merged` strings it receives:

```odin
// proxy.odin _handle_publish_diagnostics
our_items := diags_to_lsp_items(our_diags[:])   // ← leaked
merged    := merge_publish_diagnostics(ols_msg, our_items) // ← leaked
_write_to_editor_str(merged)
// No delete(our_items) or delete(merged)
```

Every `publishDiagnostics` event from OLS (fires on every file save) leaks
two heap allocations.

**Fix:**
```odin
// In diags_to_lsp_items / merge_publish_diagnostics:
sb := strings.builder_make()
defer strings.builder_destroy(&sb)
// ...
return strings.clone(strings.to_string(sb))  // clone before destroy

// In _handle_publish_diagnostics:
our_items := diags_to_lsp_items(our_diags[:])
defer delete(our_items)
merged    := merge_publish_diagnostics(ols_msg, our_items)
defer delete(merged)
_write_to_editor_str(merged)
```

---

### H4 — `_gj()` leaks intermediate strings in MCP JSON serialization
**File:** `src/mcp/tool_graph.odin:624–628`

When `_gj()` processes strings containing `\` or `"` (file paths on Windows,
messages with quotes), `strings.replace_all` allocates `e1` on
`context.allocator` (the heap). `e1` is never freed — the caller gets `e2` via
`fmt.tprintf` and `e1` is silently abandoned.

```odin
_gj :: proc(s: string) -> string {
    if !strings.contains_any(s, `"\`) { return fmt.tprintf(`"%s"`, s) }
    e1, _ := strings.replace_all(s,  `\`, `\\`)  // ← e1 leaked
    e2, _ := strings.replace_all(e1, `"`, `\"`)  // ← e2 leaked
    return fmt.tprintf(`"%s"`, e2)
}
```

Since `_gj` is called dozens of times per MCP tool response (every `name`,
`file`, `message`, `fix` field goes through it), this accumulates continuously
in the long-running MCP server.

**Fix:**
```odin
_gj :: proc(s: string) -> string {
    if !strings.contains_any(s, `"\`) { return fmt.tprintf(`"%s"`, s) }
    e1, _ := strings.replace_all(s,  `\`, `\\`)
    defer delete(e1)
    e2, _ := strings.replace_all(e1, `"`, `\"`)
    defer delete(e2)
    return fmt.tprintf(`"%s"`, e2)
}
```

---

## MEDIUM SEVERITY

---

### M1 — Incomplete JSON escaping in LSP diagnostic injection
**File:** `src/lsp/diagnostic_inject.odin:41–44`

`diags_to_lsp_items` escapes `"` → `\"` and `\` → `\\` in diagnostic messages
and fix hints, but does NOT escape control characters: `\n`, `\r`, `\t`,
and other characters < 0x20. A diagnostic message containing a literal newline
(e.g., a multi-line fix hint) will produce malformed JSON in the LSP
`publishDiagnostics` notification, potentially breaking the editor's parser.

**Fix:** Replace the two `strings.replace_all` calls with a proper JSON string
writer that escapes all control characters per RFC 8259 §7.

---

### M2 — Bracket matching in `merge_publish_diagnostics` is naive
**File:** `src/lsp/diagnostic_inject.odin:77–87`

The function finds the closing `]` of the `"diagnostics":[...]` array by
counting `[` and `]` characters. It does not account for `[` or `]` appearing
inside JSON string values (e.g., a diagnostic message `"use arr[i]"` would
prematurely close the depth counter).

```odin
for arr_end < len(s) && depth > 0 {
    switch s[arr_end] {
    case '[': depth += 1
    case ']': depth -= 1  // ← fires on ] inside "arr[i]" message string
    }
```

Result: merged notification is malformed, editor receives invalid JSON.

**Fix:** Add state tracking for whether the cursor is inside a quoted string:
```odin
in_string, escaped := false, false
for arr_end < len(s) && depth > 0 {
    c := s[arr_end]
    if escaped            { escaped = false }
    else if c == '\\'     { escaped = true }
    else if c == '"'      { in_string = !in_string }
    else if !in_string {
        if      c == '[' { depth += 1 }
        else if c == ']' { depth -= 1 }
    }
    if depth > 0 { arr_end += 1 }
}
```

---

### M3 — LSP proxy `ProxyState` and `ThreadBData` allocated but never freed
**File:** `src/lsp/proxy.odin:177–183`

```odin
state   := new(ProxyState)   // never freed
tb_data := new(ThreadBData)  // never freed
```

In practice these live for the lifetime of the process (editor session), so the
OS reclaims them on exit. However, `state.doc_cache` contains heap-allocated
strings that should be cleaned up before exit to avoid tools like AddressSanitizer
or Valgrind reporting false positives.

**Fix:** Before process exit (after `ols_stop`):
```odin
for uri, content in state.doc_cache { delete(uri); delete(content) }
delete(state.doc_cache)
free(state)
free(tb_data)
```

---

### M4 — TreeSitterASTParser shared across threads (latent risk)
**File:** `src/lsp/proxy.odin:108, 163`

Tree-sitter parsers are documented as not thread-safe. Currently `ts_parser` is
only accessed from Thread B (Thread A never calls `analyze_content`), so there
is no active race. But the state is physically shared via `state.ts_parser` and
any future modification that triggers analysis from Thread A would introduce a
silent data corruption bug.

**Fix:** Document the constraint with an explicit comment and/or add a mutex
around parser access so that any future Thread A analysis automatically gets
the lock.

---

### M5 — Pass 4 `sq.stmt_finalize` is deferred but error path skips it
**File:** `src/core/dna_exporter.odin:554–565`

```odin
vs, vok := sq.db_prepare(db.conn, `SELECT lint_violations ...`)
if !vok { continue }          // ← no finalize needed here (prepare failed)
sq.stmt_bind_i64(&vs, 1, node_id)
existing := ""
if sq.stmt_step(&vs) { existing = sq.stmt_col_text(&vs, 0) }
sq.stmt_finalize(&vs)         // ← finalize only on success path
// But if error occurs between prepare and finalize, handle leaks
```

The `sq.stmt_finalize(&vs)` call on the last line is correct for the happy
path, but if any code is added between `sq.stmt_bind_i64` and `sq.stmt_finalize`
and returns early, `vs` is not finalized.

**Fix:** Move finalize to a `defer`:
```odin
vs, vok := sq.db_prepare(db.conn, `SELECT lint_violations ...`)
if !vok { continue }
defer sq.stmt_finalize(&vs)   // ← always runs, even on early return
```

---

### M6 — `c202_find_var_type` scans unlimited lines backward
**File:** `src/core/c202-COR-SwitchExhaust.odin:120–150`

The function scans from `switch_line` all the way back to line 0 searching
for `var_name: TypeName`. For a switch 500 lines into a large procedure, this
scans 500 lines per switch statement. With many switches in large files this
becomes O(switches × file_size).

**Fix:** Cap the backward scan at a reasonable distance (e.g., 50 lines), which
covers all realistic local-variable declaration patterns:
```odin
search_from := min(switch_line, len(lines)-1)
search_limit := max(0, search_from - 50)  // look back at most 50 lines
for i := search_from; i >= search_limit; i -= 1 {
```

---

### M7 — TOML parser silently accepts invalid integer bounds
**File:** `src/core/config.odin:175`

`c020_min_length` parsed from TOML has no range validation. Values like `0`,
`-5`, or `10000` are accepted silently and used directly as a threshold,
causing either no-op behavior or excessive noise.

**Fix:**
```odin
if n, ok := strconv.parse_int(val); ok && n >= 1 && n <= 100 {
    cfg.naming_c020_min_length = n
}
```

---

## LOW SEVERITY

---

### L1 — `suppression_summary` leaks `lines` dynamic array
**File:** `src/core/suppression.odin:176–200`

`suppression_summary` builds a `[dynamic]string` and returns
`strings.join(lines[:], "\n")` without deleting `lines`. This only matters
if `suppression_summary` is called (it is only used in debugging/test paths),
but the leak is straightforward to fix:

```odin
lines: [dynamic]string
defer { for l in lines { delete(l) }; delete(lines) }
```

---

### L2 — `_gj` not used from temp_allocator context in hot JSON builders
**File:** `src/mcp/tool_graph.odin` (multiple handlers)

The JSON string builders in tool handlers accumulate temporary string
allocations from `_gj()` on `context.allocator` rather than
`context.temp_allocator`. While the MCP loop's `free_all(context.temp_allocator)`
cleans up temp-allocator memory, default-allocator strings from `_gj` are only
freed when the H4 fix above is applied.

This is resolved by the H4 fix.

---

### L3 — `autofix.odin` context start line can reach 0
**File:** `src/core/autofix.odin:208`

In `propose_fixes`, the context window is `ctx_start = e.line - 3`. If
`e.line <= 3`, `ctx_start` would be 0 or negative. The `lines[i-1]` access
inside the loop would then compute `lines[-1]` for `i=0`.

```odin
ctx_start := e.line - 3
// ...
for i := ctx_start; i < e.line && i <= len(lines); i += 1 {
    fmt.printf(" %4d | %s\n", i, lines[i-1])  // ← i-1 can be -1 if i=0
}
```

**Fix:** `ctx_start := max(1, e.line - 3)`

---

### L4 — Duplicate `is_ident_char` helpers across rule files
**Files:** `c202-COR-SwitchExhaust.odin`, `c203-COR-DeferScope.odin`,
`c019-STY-TypeMarker.odin`, `c015-DEA-UnusedConst.odin`

Four independent `@(private="file")` `is_ident_char`-style functions exist with
identical or near-identical implementations. Not a bug, but a maintenance risk
— if the definition of "identifier character" needs updating (e.g., Unicode
support), all four need changing.

**Fix:** Promote one canonical `is_ident_char(c: u8) -> bool` to a shared
internal utility in a new `src/core/text_utils.odin` or `src/core/ast.odin`.

---

## Non-Issues (Investigated and Cleared)

- **`fmt.aprintf` for diagnostic messages**: Intentionally heap-allocated.
  Diagnostics are owned by the collector and freed by the CLI/MCP output layer
  or abandoned at process exit. Not a leak in the problematic sense.

- **`b002_majority_name` value ownership in main.odin**: Returns
  `strings.clone(best_name)`. The `dir_pkg_names` map's defer loop correctly
  calls `delete(v)` for every value. ✓

- **Proxy race condition on `doc_cache`**: `strings.clone(cached_content)` on
  proxy.odin line 93 happens INSIDE the mutex (lock at 91, unlock at 94). ✓

- **`graph_get_enum_members` return type**: Returns `[]string` (slice of a
  heap-allocated `[dynamic]string`). Callers use the pattern
  `defer { for m in members { delete(m) }; delete(members) }` which correctly
  frees the backing array. ✓

- **C201 graph DB defer placement**: The comment at main.odin:341 is correct
  and the defer is at the right scope — a surviving example of explicitly
  documented defer scoping discipline. ✓

---

## Fix Priority

| Priority | Issues | Rationale |
|----------|--------|-----------|
| **Fix immediately** | H1, H2, H3, H4 | Active memory growth in long-running processes |
| **Fix before wider use** | M1, M2 | Protocol correctness (LSP JSON validity) |
| **Fix for robustness** | M3, M4, M5, M6, M7 | Defensive code / performance |
| **Cleanup pass** | L1, L2, L3, L4 | Code quality / maintenance |

---

## Files Requiring Changes

```
src/mcp/tool_graph.odin           H1, H4
src/core/c001-COR-Memory.odin     H2
src/core/c011-FFI-Safety.odin     H2
src/core/c019-STY-TypeMarker.odin H2
src/core/c101-CTX-Integrity.odin  H2
src/core/c201-COR-UncheckedResult H2
src/core/c202-COR-SwitchExhaust   H2, M6
src/core/c203-COR-DeferScope      H2
src/lsp/diagnostic_inject.odin    H3, M1, M2
src/lsp/proxy.odin                H3, M3, M4
src/core/dna_exporter.odin        M5
src/core/config.odin              M7
src/core/suppression.odin         L1
src/core/autofix.odin             L3
```
