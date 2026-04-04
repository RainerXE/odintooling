# C002 Implementation Improvement Plan - Phase 2

## Critical Issues Identified

### 1. Global Mutable State Problem (HIGH PRIORITY)
**Issue**: `c002_allocations_map`, `c002_current_scope`, and `c002_reassignments` are package-level globals causing state bleeding between files and potential concurrency issues.

**Solution**: 
- Create `C002AnalysisContext` struct to hold all mutable state
- Pass context through call chain instead of using globals
- Reset context for each file analysis

```odin
C002AnalysisContext :: struct {
    allocations_map: map[string][]C002AllocationInfo,
    current_scope: int,
    reassignments: map[string]bool,
}
```

### 2. Struct Literal Syntax Errors (BLOCKER)
**Issue**: Mixed `=` and `:` syntax in struct literals (lines 100-104, 138-148)

**Fix**: Standardize on `field = value` syntax throughout:
```odin
// WRONG:
Diagnostic{
    file = "",
    line: line,  // ← mixed syntax
    column: col,  // ← mixed syntax
}

// CORRECT:
Diagnostic{
    file = "",
    line = line,
    column = col,
}
```

### 3. Slice Mutation Clarity
**Issue**: Using plain slices instead of dynamic arrays makes intent unclear

**Fix**: Change to `[dynamic]C002AllocationInfo` for clarity:
```odin
// Current:
c002_allocations_map: map[string][]C002AllocationInfo

// Fixed:
c002_allocations_map: map[string][dynamic]C002AllocationInfo
```

### 4. Name Blocklist Problem
**Issue**: `is_suspicious_pointer_usage` uses string matching on variable names, causing false positives

**Fix**: Replace with structural/dataflow analysis:
- Track actual pointer allocations and usage
- Analyze AST relationships instead of string patterns
- Remove hardcoded name checks (ptr2, temp, copy, etc.)

### 5. API Compatibility Issues
**Issue**: `strings.index_of` doesn't exist, should be `strings.index`

**Fix**: Update all string operations:
```odin
// WRONG:
start_idx := strings.index_of(text, "free(")

// CORRECT:
start_idx := strings.index(text, "free(")
```

### 6. strings.trim Usage
**Issue**: `strings.trim` called with wrong syntax

**Fix**: Use proper slice syntax and cutset:
```odin
// WRONG:
var_name := strings.trim(text[start_idx..end_idx])

// CORRECT:
var_name := strings.trim(text[start_idx..=end_idx], " \t")
```

### 7. Declaration vs Reassignment
**Issue**: `is_pointer_reassignment` triggers on initial declarations (`:=`)

**Fix**: Distinguish between declaration and reassignment:
```odin
is_pointer_reassignment :: proc(node: ^ASTNode) -> bool {
    // Only trigger on = (reassignment), not := (declaration)
    return strings.contains(node.node_type, "assignment") &&
           strings.contains(node.text, "=") &&
           !strings.contains(node.text, ":=")
}
```

## Architecture Issues

### 8. Missing Allocation Tracking
**Issue**: No `c002_markAsAllocated` function - allocations never tracked

**Fix**: Implement allocation tracking:
```odin
c002_markAsAllocated :: proc(ctx: ^C002AnalysisContext, var_name: string, line: int, col: int) {
    allocation := C002AllocationInfo{
        var_name = var_name,
        line = line,
        col = col,
        is_freed = false,
        free_count = 0,
        scope_level = ctx.current_scope,
        is_reassigned = false,
    }
    ctx.allocations_map[var_name] = append(ctx.allocations_map[var_name], allocation)
}
```

### 9. Single Diagnostic Return
**Issue**: `c002Matcher` returns single Diagnostic, missing multiple violations

**Fix**: Return `[]Diagnostic` to match C001 interface:
```odin
c002Matcher :: proc(file_path: string, node: ^ASTNode, ctx: ^C002AnalysisContext) -> []Diagnostic {
    var diagnostics: []Diagnostic
    // ... analysis code ...
    // diagnostics = append(diagnostics, diagnostic)
    return diagnostics
}
```

### 10. Scope Tracking Reliability
**Issue**: Double-counting when entering proc bodies (proc + block nodes)

**Fix**: Unify scope boundary detection:
```odin
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block") ||
           strings.contains(node.node_type, "proc") ||
           strings.contains(node.node_type, "for") ||
           strings.contains(node.node_type, "if") ||
           strings.contains(node.node_type, "case")
}

// Only increment once per boundary
if is_scope_boundary(node) && is_entering_scope(node) {
    ctx.current_scope += 1
}
```

### 11. Deduplication Missing
**Issue**: C002 not using `dedupDiagnostics` like C001

**Fix**: Wire through same deduplication path in `main.odin`

### 12. Error Handling
**Issue**: Wrong error check for `os.read_entire_file_from_path`

**Fix**: Update error handling:
```odin
// WRONG:
content, err := os.read_entire_file_from_path(file_path)
if err != nil { /* ... */ }

// CORRECT:
content, ok := os.read_entire_file_from_path(file_path)
if !ok { /* ... */ }
```

## Implementation Plan

### Phase 1: Fix Compilation Errors (BLOCKER)
1. Fix struct literal syntax errors
2. Fix `strings.index_of` → `strings.index`
3. Fix `strings.trim` usage and slice syntax
4. Test compilation

### Phase 2: Fix Core Logic
1. Implement `C002AnalysisContext` struct
2. Add `c002_markAsAllocated` function
3. Fix scope tracking reliability
4. Change return type to `[]Diagnostic`

### Phase 3: Improve Analysis Quality
1. Replace name blocklist with structural analysis
2. Fix declaration vs reassignment detection
3. Add proper allocation tracking
4. Wire through deduplication

### Phase 4: Testing and Validation
1. Update test cases for new behavior
2. Validate no false positives
3. Confirm all real issues detected
4. Performance testing

## Priority Order

1. **BLOCKER**: Fix compilation errors (syntax, API calls)
2. **HIGH**: Fix global state with context struct
3. **HIGH**: Implement allocation tracking
4. **MEDIUM**: Improve analysis quality (remove blocklist)
5. **LOW**: Optimize and clean up

## Expected Outcome

After implementation:
- ✅ Compiles without errors
- ✅ No state bleeding between files
- ✅ Detects real pointer safety issues
- ✅ No false positives from name matching
- ✅ Handles multiple violations per file
- ✅ Thread-safe architecture
- ✅ Consistent with C001 patterns