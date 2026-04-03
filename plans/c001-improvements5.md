# C001 Improvements - Phase 5: Bug Fixes and Refinements

## Overview
This phase addresses remaining bugs and oversights identified in the C001 rule implementation. Focus on critical memory safety issues, path exclusion accuracy, and diagnostic reporting completeness.

## Priority Issues (Must Fix)

### Bug 1: Memory Leak in `check_block_for_c001`
**Severity**: High 🟠
**Location**: `src/core/c001.odin`
**Problem**: 
- `defer delete(content)` is inside the `if err == nil` block but executes at function exit
- `strings.split` allocates `file_lines` which is never freed
- Creates dangling references if `file_lines` is used after `content` deletion

**Fix**:
```odin
// Move defer outside if block and add cleanup for file_lines
content, err := os.read_entire_file_from_path(file_path, context.allocator)
if err != nil {
    return {}
}
defer delete(content)
content_str := string(content)
file_lines := strings.split(content_str, "\n")
defer delete(file_lines)
```

### Bug 5: Path Exclusion False Positives
**Severity**: High 🟠
**Location**: `src/core/c001.odin` - `should_exclude_file`
**Problem**: Current implementation excludes files containing "core/" or "vendor/" anywhere in path, causing false exclusions for legitimate projects.

**Fix**:
```odin
// Replace string contains with path component matching
if strings.contains(file_path, "/core/") ||
   strings.contains(file_path, "/vendor/") ||
   strings.has_suffix(file_path, "/core") ||
   strings.has_suffix(file_path, "/vendor") {
    return true
}
```

### Bug 8: Diagnostic Wrapper Returns Only First Issue
**Severity**: High 🟠
**Location**: `src/core/c001.odin` - `c001MatcherWrapper`
**Problem**: Wrapper returns only first diagnostic, hiding multiple violations per file.

**Fix**:
1. Update `main.odin` to call `c001Matcher` directly instead of through `Rule.matcher`
2. Remove `c001MatcherWrapper` entirely
3. If `main.odin` interface requires single return, update Rule struct to support `[]Diagnostic`

## Medium Priority Issues

### Bug 2: Wrong Node for Allocator Check
**Severity**: Medium 🟡
**Location**: `src/core/c001.odin` - `uses_non_default_allocator` call
**Problem**: Uses assignment node instead of call expression node for line number lookup.

**Fix**:
```odin
// Find the call_expression child node before calling uses_non_default_allocator
call_node := find_call_expression_child(&child)
if call_node != nil {
    if uses_non_default_allocator(call_node, file_lines) {
        // handle non-default allocator
    }
}
```

### Bug 6: Suppression Scope Ambiguity
**Severity**: Medium 🟡
**Location**: `src/core/c001.odin` - `collect_suppressions`
**Problem**: Current implementation suppresses both line N and N+1 for a suppression on line N-1.

**Design Decision Needed**:
- Option A: Keep current behavior (suppression applies to next allocation regardless of line)
- Option B: Make suppression line-specific (only suppress allocation on exact next line)

**Recommended**: Option A with clear documentation

### Oversight 3: Performance Critical Path Incomplete
**Severity**: Low 🟢
**Location**: `src/core/c001.odin` - `is_performance_critical_block`
**Problem**: Changes diagnostic type but not message text.

**Fix**:
```odin
if ctx.is_performance_critical {
    message_text = "[C001] Allocation in performance-critical block — verify intentional"
    fix_text = "Add defer free() ... // Performance marker detected"
    diag_type = DiagnosticType.CONTEXTUAL
}
```

## Low Priority Issues

### Bug 3: Multi-Variable Declarations
**Severity**: Low 🟢
**Location**: `src/core/c001.odin` - `extract_lhs_name`
**Problem**: Only tracks first variable in multi-variable declarations.

**Documentation**: Add to limitations section:
```
// Known Limitation: Multi-variable declarations like `a, b := make(...), make(...)`
// only track the first variable (a). This is acceptable for v1.
```

### Bug 4: Redundant Name Extraction
**Severity**: Low 🟢
**Location**: `src/core/c001.odin` - `has_manual_cleanup`
**Problem**: Re-extracts variable name that caller already has.

**Fix**:
```odin
// Change signature
has_manual_cleanup :: proc(var_name: string, block: ^ASTNode) -> bool {
    // use var_name directly
}

// Update call sites
if has_manual_cleanup(var_name, block) {
    // ...
}
```

### Oversight 5: Dead Comment
**Severity**: Low 🟢
**Location**: `src/core/c001.odin` line 116
**Problem**: Commented-out duplicate procedure declaration.

**Fix**: Remove line 116 entirely

## Implementation Plan

### Phase 5A: Critical Fixes (Immediate)
1. Fix memory leak in `check_block_for_c001` (Bug 1)
2. Fix path exclusion logic (Bug 5)
3. Fix diagnostic wrapper to return all issues (Bug 8)
4. Verify fixes with test suite

### Phase 5B: Medium Priority (Next)
1. Fix allocator node lookup (Bug 2)
2. Document suppression behavior (Bug 6)
3. Complete performance-critical messaging (Oversight 3)
4. Test with real codebases

### Phase 5C: Low Priority (Cleanup)
1. Document multi-variable limitation (Bug 3)
2. Optimize name extraction (Bug 4)
3. Remove dead comment (Oversight 5)
4. Final test pass

## Testing Strategy

1. **Unit Tests**: Verify each fix in isolation
2. **Integration Tests**: Run full test suite
3. **Real Codebases**: Test on Odin core, base, OLS, RuiShin
4. **Regression Tests**: Ensure no new false positives introduced

## Success Criteria

- ✅ No memory leaks in linter code itself
- ✅ Accurate path exclusion (no false exclusions)
- ✅ All violations reported (no truncation)
- ✅ Zero false positives in production code
- ✅ Clear documentation of limitations

## Timeline

- Phase 5A: 1 day (critical fixes)
- Phase 5B: 1 day (medium priority)
- Phase 5C: 0.5 day (cleanup)
- Testing: 1 day

**Total**: 3.5 days to production-ready state
