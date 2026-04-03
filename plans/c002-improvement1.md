# C002 Implementation Fix Plan

## 🎯 Objective
Fix the fundamental issues in C002 implementation to properly detect pointer safety violations as defined by the test cases.

## 🔍 Root Cause Analysis

### Current Implementation Problems

1. **Fundamental Logic Error**
   ```odin
   // Current (WRONG):
   if c002_isFreeNode(node) {
       var_name := c002_extractVariableName(node)
       c002_markAsFreed(var_name)  // Marks ALL allocations as freed
   }
   ```
   **Problem**: This marks all allocations of a variable as freed, even if only one defer free exists.

2. **Missing Defer Counting**
   ```odin
   C002AllocationInfo :: struct {
       var_name: string,
       line: int,
       col: int,
       is_freed: bool,  // Only boolean - can't track multiple defers
   }
   ```
   **Problem**: Can't distinguish between single and multiple frees.

3. **Wrong Detection Logic**
   ```odin
   // Current logic checks for unfreed allocations
   // Should check for OVER-freed allocations
   ```
   **Problem**: Backwards logic - detects missing frees instead of extra frees.

4. **No Scope Tracking**
   **Problem**: Can't handle nested blocks, shadowing, or scope boundaries.

5. **Fragile String Matching**
   ```odin
   strings.contains(node.text, "free")  // Error-prone
   ```
   **Problem**: Should use proper AST node type checking.

## 🧠 Correct Implementation Strategy

### Core Requirements

1. **Individual Allocation Tracking**
   - Each `make()`/`new()` gets unique allocation ID
   - Track lifetime independently

2. **Defer Counting**
   - Count how many times each allocation is deferred for free
   - Detect when count > 1

3. **Scope Awareness**
   - Track scope entry/exit
   - Handle nested blocks correctly
   - Detect scope shadowing

4. **Proper Detection**
   - Cross-reference allocations with frees
   - Report allocations freed multiple times
   - Report allocations never freed (memory leaks)

### Data Structures Needed

```odin
// Individual allocation tracking
AllocationRecord :: struct {
    allocation_id: int,      // Unique ID for this allocation
    var_name: string,        // Variable name
    line: int,               // Source line
    col: int,                // Source column
    scope_depth: int,        // Nesting level
    free_count: int,         // Number of defer frees
    is_freed: bool,          // Has been freed
    free_locations: [dynamic]{int, int}, // Where it was freed
}

// Scope-aware tracking
ScopeContext :: struct {
    depth: int,
    allocations: map[int]AllocationRecord, // allocation_id -> record
    variable_map: map[string][]int,        // var_name -> [allocation_ids]
}

// Global tracking
c002_scope_stack: [dynamic]ScopeContext
c002_current_scope: ScopeContext
c002_next_allocation_id: int
```

### Correct Algorithm

```odin
// Scope management
c002_push_scope :: proc(depth: int) {
    new_scope = ScopeContext{depth: depth, allocations: {}, variable_map: {}}
    c002_scope_stack = append(c002_scope_stack, new_scope)
    c002_current_scope = new_scope
}

c002_pop_scope :: proc() -> [dynamic]Diagnostic {
    diagnostics: [dynamic]Diagnostic
    
    // Check for issues before popping
    for &alloc_id, alloc in c002_current_scope.allocations {
        if alloc.free_count == 0 {
            // Memory leak - never freed
            diagnostics |= create_leak_diagnostic(alloc)
        } else if alloc.free_count > 1 {
            // Double free - freed multiple times
            diagnostics |= create_double_free_diagnostic(alloc)
        }
    }
    
    // Pop the scope
    if len(c002_scope_stack) > 1 {
        c002_scope_stack = c002_scope_stack[0..<len(c002_scope_stack)-1]
        c002_current_scope = c002_scope_stack[len(c002_scope_stack)-1]
    }
    
    return diagnostics
}

// Allocation tracking
c002_track_allocation :: proc(var_name: string, line: int, col: int) {
    alloc_id = c002_next_allocation_id
    c002_next_allocation_id++
    
    record = AllocationRecord{
        allocation_id: alloc_id,
        var_name: var_name,
        line: line,
        col: col,
        scope_depth: c002_current_scope.depth,
        free_count: 0,
        is_freed: false,
        free_locations: {},
    }
    
    c002_current_scope.allocations[alloc_id] = record
    c002_current_scope.variable_map[var_name] |= alloc_id
}

// Free tracking
c002_track_free :: proc(var_name: string, line: int, col: int) {
    if c002_current_scope.variable_map[var_name] {
        for alloc_id in c002_current_scope.variable_map[var_name] {
            alloc = c002_current_scope.allocations[alloc_id]
            alloc.free_count++
            alloc.free_locations |= {line, col}
            c002_current_scope.allocations[alloc_id] = alloc
        }
    }
}
```

## 🛠️ Implementation Plan

### Phase 1: Fix Core Tracking (Critical)

**Todo c002-1**: Fix fundamental logic error
- Replace `c002_markAsFreed()` with proper counting
- Change from boolean to integer tracking
- Fix the backwards detection logic

**Todo c002-2**: Add allocation ID system
- Generate unique IDs for each allocation
- Track allocations individually
- Replace variable-only tracking

**Todo c002-3**: Implement defer counting
- Add `free_count` field to tracking struct
- Increment on each defer free
- Detect when count > 1

**Todo c002-4**: Add scope boundary tracking
- Implement `c002_push_scope()` and `c002_pop_scope()`
- Track scope depth
- Handle nested blocks correctly

**Todo c002-5**: Fix C002AllocationInfo struct
```odin
AllocationRecord :: struct {
    allocation_id: int,
    var_name: string,
    line: int,
    col: int,
    scope_depth: int,
    free_count: int,  // NEW: Count defer frees
    free_locations: [dynamic]{int, int}, // NEW: Track where freed
}
```

### Phase 2: Enhance Detection

**Todo c002-6**: Replace string-based detection with AST nodes
- Use proper tree-sitter node types
- Check `node.type` instead of string contents
- More reliable and maintainable

**Todo c002-7**: Add reassignment tracking
- Detect when variable is assigned new allocation
- Mark old allocation as orphaned
- Track pointer lifetime correctly

**Todo c002-8**: Implement cross-referencing
- At scope exit, verify all allocations
- Report double frees
- Report memory leaks
- Generate precise diagnostics

### Phase 3: Test Integration

**Todo c002-9**: Test with `c002_explicit_violation.odin`
- Should detect double frees
- Verify correct line/column reporting
- Ensure no false positives

**Todo c002-10**: Test with `c002_fixture_fail.odin`
- Should detect wrong pointer usage
- Verify all test cases pass
- Ensure comprehensive coverage

## 📋 Execution Order

1. **Fix data structures** (c002-5)
2. **Add scope tracking** (c002-4)
3. **Fix core logic** (c002-1)
4. **Add defer counting** (c002-3)
5. **Add allocation IDs** (c002-2)
6. **Replace string matching** (c002-6)
7. **Add reassignment tracking** (c002-7)
8. **Implement cross-referencing** (c002-8)
9. **Test explicit violations** (c002-9)
10. **Test all cases** (c002-10)

## 🎯 Success Criteria

### Minimum Viable Fix
- ✅ Detect double frees (c002_explicit_violation.odin)
- ✅ Detect wrong pointer usage (c002_fixture_fail.odin)
- ✅ No false positives on valid code
- ✅ Proper error messages with locations

### Complete Implementation
- ✅ Handle all edge cases
- ✅ Scope-aware analysis
- ✅ Reassignment tracking
- ✅ Memory leak detection
- ✅ 100% test coverage

## 📊 Progress Tracking

| Phase | Status | Coverage Target |
|-------|--------|-----------------|
| Phase 1: Core Tracking | ⏳ Pending | 50-70% |
| Phase 2: Enhanced Detection | ⏳ Pending | 85-95% |
| Phase 3: Test Integration | ⏳ Pending | 100% |

## 🔧 Technical Notes

### AST Node Types to Use
Instead of string matching, use proper tree-sitter types:
- `call_expression` for function calls
- `identifier` for variable names
- `defer_statement` for defer keywords
- `block` for scope boundaries

### Error Handling
- Handle edge cases gracefully
- Provide clear error messages
- Include fix suggestions
- Point to exact line/column

### Performance
- Use efficient data structures
- Minimize memory allocations
- Optimize lookups
- Consider large codebases

## 📖 References

- Test cases: `tests/C002_COR_POINTER/`
- Current implementation: `src/core/c002-COR-Pointer.odin`
- Gap analysis: `plans/C002-IMPLEMENTATION-GAPS-ANALYSIS.md`
- Tree-sitter docs: https://tree-sitter.github.io/tree-sitter/

## 🎓 Conclusion

This plan addresses the **fundamental flaws** in the current C002 implementation and provides a **clear path** to a robust, comprehensive pointer safety analyzer. The approach is **incremental** and **test-driven**, ensuring each step delivers measurable progress toward the goal of detecting all pointer safety violations defined by the test cases.