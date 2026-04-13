# C002 Incremental Improvement Plan

## 🎯 Objective
Enhance C002 implementation through small, testable steps to detect more pointer safety violations while maintaining zero false positives.

## 🔍 Lessons from Failed Rewrite

### What Went Wrong
1. **Overengineering**: Tried to solve all problems at once
2. **Syntax Complexity**: Odin array/struct initialization is tricky
3. **Scope Creep**: Started with defer counting, ended up rewriting everything
4. **Testing Gap**: Hard to validate intermediate states

### New Strategy: Incremental Improvement
- **Small, testable steps** (each modifies <10 lines)
- **Clear validation** (specific test case per step)
- **No regressions** (all existing tests must pass)
- **Production ready** at each stage

## 📋 Step-by-Step Plan

### STEP 1: Add Defer Counting (Critical Fix)

**Problem**: Current implementation can't detect multiple defer frees on same allocation

**Solution**: Add `free_count` field and increment on each defer free

**Test Case**: `c002_explicit_violation.odin` (should detect double frees)

**Implementation**:
```odin
// 1. Modify C002AllocationInfo struct
C002AllocationInfo :: struct {
    var_name: string,
    line: int,
    col: int,
    is_freed: bool,
    free_count: int,  // NEW: Track number of defer frees
}

// 2. Update c002_markAsFreed to count instead of boolean
c002_markAsFreed :: proc(var_name: string, line: int, col: int) {
    if len(c002_allocations_map[var_name]) > 0 {
        existing := c002_allocations_map[var_name]
        for i in 0..<len(existing) {
            existing[i].free_count += 1  // Increment instead of setting true
            
            // NEW: Detect and report double free
            if existing[i].free_count > 1 {
                return Diagnostic{
                    file: "",
                    line: line,
                    column: col,
                    rule_id: "C002",
                    tier: "correctness",
                    message: "C002 [correctness] Multiple defer frees on same allocation",
                    fix: fmt.tprintf("Allocation at line %d,%d freed %d times", 
                                    existing[i].line, existing[i].col, existing[i].free_count),
                    has_fix: true,
                    diag_type: .VIOLATION,
                }
            }
        }
        c002_allocations_map[var_name] = existing
    }
    return Diagnostic{}
}
```

**Validation**:
```bash
# Before: No C002 violations detected
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin

# After: C002 violations detected at double free locations
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin

# Regression check: No false positives
./artifacts/odin-lint tests/C002_COR_POINTER/c002_fixture_pass.odin
```

**Complexity**: Low (5-10 lines changed)
**Risk**: Low (minimal code changes)
**Benefit**: 30-40% test coverage

### STEP 2: Add Scope Boundary Tracking

**Problem**: Can't handle nested blocks and scope shadowing

**Solution**: Add scope stack to track block boundaries

**Test Case**: `c002_edge_case_scope.odin` (scope shadowing)

**Implementation**:
```odin
// Add scope tracking variables
c002_scope_stack: [dynamic]map[string][dynamic]C002AllocationInfo
c002_current_scope: map[string][dynamic]C002AllocationInfo

// Initialize in c002Matcher
c002_initScopeTracking :: proc() {
    c002_scope_stack = {}
    c002_current_scope = {}
    c002_scope_stack = append(&c002_scope_stack, c002_current_scope)
}

// Push scope when entering block
c002_push_scope :: proc() {
    new_scope: map[string][dynamic]C002AllocationInfo = {}
    c002_scope_stack = append(&c002_scope_stack, new_scope)
    c002_current_scope = new_scope
}

// Pop scope when exiting block
c002_pop_scope :: proc() -> Diagnostic {
    diagnostics: [dynamic]Diagnostic
    
    // Check for double frees in current scope
    for &var_name, allocations in c002_current_scope {
        for alloc in allocations {
            if alloc.free_count > 1 {
                diag: Diagnostic
                diag.file = ""
                diag.line = alloc.line
                diag.column = alloc.col
                diag.rule_id = "C002"
                diag.tier = "correctness"
                diag.message = "C002 [correctness] Multiple defer frees in scope"
                diag.fix = "Check scope boundary handling"
                diag.has_fix = true
                diag.diag_type = .VIOLATION
                diagnostics = append(&diagnostics, diag)
            }
        }
    }
    
    // Pop scope
    if len(c002_scope_stack) > 1 {
        c002_scope_stack = c002_scope_stack[0..<len(c002_scope_stack)-1]
        c002_current_scope = c002_scope_stack[len(c002_scope_stack)-1]
    }
    
    return diagnostics[0] if len(diagnostics) > 0 else Diagnostic{}
}

// Modify matcher to handle blocks
c002Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // Initialize on first call
    if len(c002_scope_stack) == 0 {
        c002_initScopeTracking()
    }
    
    // Push scope for blocks
    if strings.contains(node.node_type, "block") {
        c002_push_scope()
    }
    
    // Existing allocation/free tracking...
    
    // Pop scope for blocks
    if strings.contains(node.node_type, "block") {
        return c002_pop_scope()
    }
    
    return Diagnostic{}
}
```

**Validation**:
```bash
# Test scope handling
./artifacts/odin-lint tests/C002_COR_POINTER/c002_edge_case_scope.odin

# Regression checks
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin
./artifacts/odin-lint tests/C002_COR_POINTER/c002_fixture_pass.odin
```

**Complexity**: Medium (20-30 lines, scope management)
**Risk**: Medium (requires careful boundary handling)
**Benefit**: 50-60% test coverage

### STEP 3: Add Reassignment Tracking

**Problem**: Misses cases where pointer is reassigned before free

**Solution**: Track when variables are assigned new allocations

**Test Case**: `c002_edge_case_reassignment.odin`

**Implementation**:
```odin
// Add field to track reassignment
C002AllocationInfo :: struct {
    var_name: string,
    line: int,
    col: int,
    is_freed: bool,
    free_count: int,
    is_orphaned: bool,  // NEW: Mark if reassigned
}

// Detect reassignment in allocation tracking
c002_track_allocation :: proc(var_name: string, line: int, col: int) {
    // If variable already has allocations, mark them as orphaned
    if len(c002_allocations_map[var_name]) > 0 {
        for i in 0..<len(c002_allocations_map[var_name]) {
            if !c002_allocations_map[var_name][i].is_freed {
                // Orphaned allocation - will cause memory leak
                existing := c002_allocations_map[var_name]
                existing[i].is_orphaned = true
                c002_allocations_map[var_name] = existing
            }
        }
    }
    
    // Add new allocation
    new_alloc := C002AllocationInfo{
        var_name: var_name,
        line: line,
        col: col,
        is_freed: false,
        free_count: 0,
        is_orphaned: false,
    }
    c002_allocations_map[var_name] = append(c002_allocations_map[var_name], new_alloc)
}

// Check for orphaned allocations in c002_markAsFreed
if alloc.is_orphaned && alloc.free_count == 1 {
    return Diagnostic{
        file: "",
        line: line,
        column: col,
        rule_id: "C002",
        tier: "correctness",
        message: "C002 [correctness] Freeing reassigned pointer",
        fix: "Original allocation was lost due to reassignment",
        has_fix: true,
        diag_type: .VIOLATION,
    }
}
```

**Validation**:
```bash
# Test reassignment detection
./artifacts/odin-lint tests/C002_COR_POINTER/c002_edge_case_reassignment.odin

# All regression checks
./scripts/run_c002_tests.sh
```

**Complexity**: Medium (pointer lifetime tracking)
**Risk**: Medium (requires careful state management)
**Benefit**: 70-80% test coverage

### STEP 4: Memory Leak Detection (Optional)

**Problem**: Doesn't report allocations that are never freed

**Solution**: Check for unfreed allocations at scope exit

**Test Case**: Create new test for memory leaks

**Implementation**:
```odin
// Enhance c002_pop_scope to detect memory leaks
c002_pop_scope :: proc() -> Diagnostic {
    diagnostics: [dynamic]Diagnostic
    
    // Check for double frees
    for &var_name, allocations in c002_current_scope {
        for alloc in allocations {
            if alloc.free_count > 1 {
                // Double free (already handled in step 1)
            } else if alloc.free_count == 0 && !alloc.is_orphaned {
                // Memory leak - never freed
                diag: Diagnostic
                diag.file = ""
                diag.line = alloc.line
                diag.column = alloc.col
                diag.rule_id = "C002"
                diag.tier: "correctness"
                diag.message = "C002 [correctness] Allocation never freed (memory leak)"
                diag.fix = fmt.tprintf("Add 'defer free(%s)' at line %d", var_name, alloc.line)
                diag.has_fix = true
                diag.diag_type = .VIOLATION
                diagnostics = append(&diagnostics, diag)
            }
        }
    }
    
    // Pop scope (existing code)
    // ...
    
    return diagnostics[0] if len(diagnostics) > 0 else Diagnostic{}
}
```

**Validation**:
```bash
# Create and test memory leak test case
# Verify all existing tests still pass
```

**Complexity**: Low (builds on existing infrastructure)
**Risk**: Low (additive functionality)
**Benefit**: 85-95% test coverage

## 📋 Execution Plan

| Step | Task | Test Case | Complexity | Status | Expected Coverage |
|------|------|-----------|------------|--------|-------------------|
| 1 | Add defer counting | `c002_explicit_violation.odin` | Low | ⏳ Pending | 30-40% |
| 2 | Add scope tracking | `c002_edge_case_scope.odin` | Medium | ⏳ Pending | 50-60% |
| 3 | Add reassignment tracking | `c002_edge_case_reassignment.odin` | Medium | ⏳ Pending | 70-80% |
| 4 | Add memory leak detection | (New test) | Low | ⏳ Pending | 85-95% |

## 🎯 Success Criteria

### After Each Step
- ✅ **Compiles**: No syntax errors
- ✅ **No Regressions**: All existing tests pass
- ✅ **New Capability**: Specific test case now passes
- ✅ **Production Ready**: Can be deployed immediately

### Final State (After Step 4)
- ✅ **Test Coverage**: 85-95% of pointer safety issues
- ✅ **No False Positives**: Zero incorrect detections
- ✅ **Comprehensive**: Handles all major pointer misuse patterns
- ✅ **Production Grade**: Ready for wide deployment

## 🧪 Testing Strategy

### Test-Driven Development
```bash
# For each step:
1. Identify test case that should pass but currently fails
2. Make minimal code change to fix it
3. Verify that test case now passes
4. Verify no existing tests break
5. Document the change
```

### Example: Step 1 Validation

**Before Step 1:**
```bash
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin
# Result: No C002 violations (missing detection) ❌
```

**After Step 1:**
```bash
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin
# Result: C002 violations at double free locations ✅
```

**Regression Check:**
```bash
./artifacts/odin-lint tests/C002_COR_POINTER/c002_fixture_pass.odin
# Result: No C002 violations (no false positives) ✅
```

## 📊 Progress Tracking

| Phase | Status | Coverage | Risk | Deployment Ready |
|-------|--------|----------|------|------------------|
| Baseline | ✅ Current | 14% | None | ✅ Yes |
| Step 1: Defer Counting | ⏳ Pending | 30-40% | Low | ✅ Yes |
| Step 2: Scope Tracking | ⏳ Pending | 50-60% | Medium | ✅ Yes |
| Step 3: Reassignment | ⏳ Pending | 70-80% | Medium | ✅ Yes |
| Step 4: Memory Leaks | ⏳ Pending | 85-95% | Low | ✅ Yes |

## 🔧 Technical Notes

### Odin-Specific Patterns
- **Array append**: Use `append(&array, element)` not `array = append(...)`
- **Struct initialization**: Field-by-field is safer than literals
- **Array slices**: Test carefully, use loops if needed
- **Optional values**: Handle explicitly with `if value, ok := map[key] {}`

### Error Handling
- Provide **clear, actionable** error messages
- Include **exact line/column** locations
- Offer **specific fix suggestions**
- Avoid **false positives** at all costs

### Performance Considerations
- Use **efficient data structures** (maps for O(1) lookups)
- **Minimize allocations** (reuse structures where possible)
- **Optimize hot paths** (allocation/free tracking)
- **Scale to large codebases** (test with big files)

## 📖 References

- **Current Implementation**: `src/core/c002-COR-Pointer.odin` (working baseline)
- **Test Cases**: `tests/C002_COR_POINTER/` (comprehensive scenarios)
- **Gap Analysis**: `plans/C002-IMPLEMENTATION-GAPS-ANALYSIS.md` (what needs fixing)
- **Tree-sitter Docs**: https://tree-sitter.github.io/tree-sitter/

## 🎓 Key Insights

1. **Working > Perfect**: Conservative detection is better than broken detection
2. **Small Steps > Giant Leaps**: Each incremental change can be tested independently
3. **Test-Driven**: Use existing test cases as specification and validation
4. **Odin Constraints**: Work within language syntax, don't fight it
5. **Production First**: Get basic version working, then enhance gradually

## 🚀 Execution Workflow

### Step 1 Implementation
```bash
# 1. Edit src/core/c002-COR-Pointer.odin
#    - Add free_count field to C002AllocationInfo
#    - Modify c002_markAsFreed to increment and detect doubles
#    - Add double free diagnostic creation

# 2. Test the change
./artifacts/odin-lint tests/C002_COR_POINTER/c002_explicit_violation.odin

# 3. Verify no regressions
./scripts/run_c002_tests.sh

# 4. Commit with clear message
git commit -m "C002: Add defer counting to detect double frees"

# 5. Update this document
#    - Mark Step 1 as completed
#    - Add actual results and metrics
```

### Step 2 Implementation
```bash
# 1. Add scope tracking variables
# 2. Implement c002_push_scope and c002_pop_scope
# 3. Modify matcher to handle block nodes
# 4. Test with scope test cases
# 5. Verify all tests pass
# 6. Commit and document
```

### And so on...

Each step follows the same pattern:
1. **Targeted code change** (<10 lines)
2. **Specific test validation** (one test case)
3. **Regression checking** (all tests)
4. **Documentation update** (this file)
5. **Commit with context** (clear git message)

## 🎯 Conclusion

This **incremental approach** learns from the failed rewrite and provides:
- ✅ **Clear path** to comprehensive C002 functionality
- ✅ **Low risk** through small, testable steps
- ✅ **Immediate value** at each stage
- ✅ **Production ready** after each successful step
- ✅ **Comprehensive documentation** of progress and decisions

**Result**: Same comprehensive detection capabilities, achieved safely and maintainably.