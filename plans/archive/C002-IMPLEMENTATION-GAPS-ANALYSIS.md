# C002 Implementation Gaps Analysis

## 🎯 Objective
This document identifies the gaps between current C002 implementation and the comprehensive pointer safety checking that should be implemented.

## 🔍 Current Implementation Status

### What C002 Currently Detects
- Basic allocation tracking with AST analysis
- Simple defer free patterns
- Conservative approach with low false positives

### What C002 Should Detect (But Currently Doesn't)

## 📋 Gap Analysis: Test Cases vs Implementation

### 1. **Double Free Detection**
**Test Case**: `c002_explicit_violation.odin`
```odin
ptr := make([]int, 50)
defer free(ptr)  // First free - correct
defer free(ptr)  // Second free - SHOULD TRIGGER C002
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Track multiple defers on same pointer in same scope

### 2. **Wrong Pointer Free Detection**
**Test Case**: `c002_fixture_fail.odin`
```odin
data1 := make([]int, 100)
data2 := make([]int, 200)
defer free(data1)  // First free
defer free(data1)  // Second free - SHOULD TRIGGER C002
defer free(data2)  // Never happens - memory leak
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Cross-reference all allocations with all frees in scope

### 3. **Reassignment Before Free**
**Test Case**: `c002_edge_case_reassignment.odin`
```odin
ptr1 := make([]int, 10)
ptr2 := make([]int, 20)
ptr1 = ptr2  // Reassignment
// Original ptr1 allocation is now lost
defer free(ptr1)  // SHOULD TRIGGER C002 - wrong pointer
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Track pointer reassignment history

### 4. **Conditional Reassignment**
**Test Case**: `c002_edge_case_conditional.odin`
```odin
data := make([]int, 50)
if condition {
    data = make([]int, 100)  // Conditional reassignment
}
defer free(data)  // SHOULD TRIGGER C002 - ambiguous which allocation
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Control flow analysis for conditional reassignments

### 5. **Scope Shadowing Issues**
**Test Case**: `c002_edge_case_scope.odin`
```odin
ptr := make([]int, 10)
defer free(ptr)  // Free outer ptr
{
    ptr := make([]int, 20)  // Shadow outer ptr
    defer free(ptr)  // Free inner ptr - correct
}
// Outer ptr was already freed above - SHOULD TRIGGER C002
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Scope-aware pointer tracking

### 6. **Function Parameter Reassignment**
**Test Case**: `c002_edge_case_scope.odin`
```odin
proc modify_pointer(ptr: ^[]int) {
    *ptr = make([]int, 25)  // Reassignment through pointer
}

original := make([]int, 15)
modify_pointer(&original)
defer free(original)  // SHOULD TRIGGER C002 - not original pointer
```
**Current Behavior**: ❌ Not detected
**Required Implementation**: Interprocedural analysis for pointer parameters

## 🛠️ Required Implementation Work

### Phase 1: Enhanced Tracking (High Priority)
- [ ] Track all defer statements per scope
- [ ] Detect multiple defers on same pointer
- [ ] Cross-reference allocations with frees
- [ ] Implement pointer reassignment tracking

### Phase 2: Advanced Analysis (Medium Priority)
- [ ] Control flow analysis for conditional patterns
- [ ] Scope-aware pointer lifetime tracking
- [ ] Interprocedural analysis for function calls
- [ ] Closure and capture analysis

### Phase 3: Complex Patterns (Future)
- [ ] Pointer arithmetic detection
- [ ] Array slicing before free analysis
- [ ] Struct field reassignment tracking
- [ ] Memory leak detection (unfreed allocations)

## 📊 Test Coverage Summary

| Test Case | Purpose | Current Status | Required Implementation |
|------------|---------|----------------|------------------------|
| `c002_fixture_pass.odin` | Valid usage | ✅ Working | None |
| `c002_fixture_fail.odin` | Wrong pointer | ❌ Not detected | Multiple defer tracking |
| `c002_explicit_violation.odin` | Double free | ❌ Not detected | Defer counting |
| `c002_edge_case_reassignment.odin` | Reassignment | ❌ Not detected | Pointer history tracking |
| `c002_edge_case_conditional.odin` | Conditional patterns | ❌ Not detected | Control flow analysis |
| `c002_edge_case_scope.odin` | Scope issues | ❌ Not detected | Scope-aware tracking |
| `c002_edge_case_complex.odin` | Complex patterns | ❌ Not detected | Advanced analysis |

## 🎯 Next Steps

### Immediate Priority
1. **Implement defer counting**: Track how many times each pointer is deferred for free
2. **Enhance pointer tracking**: Add reassignment history to allocation info
3. **Add cross-referencing**: Match allocations to frees within same scope

### Test-Driven Development Approach
- Use existing test cases as specification
- Implement features to make failing tests pass
- Maintain 100% pass rate on edge cases
- Ensure no false positives on valid code

## 📈 Success Metrics

**Current**: 1/7 test cases triggering C002 (14%)
**Target**: 6/7 test cases triggering C002 (86%)
**Stretch Goal**: 7/7 test cases with precise diagnostics (100%)

## 🔧 Technical Approach

### Data Structures Needed
```odin
// Enhanced allocation tracking
AllocationInfo :: struct {
    var_name: string,
    line: int,
    col: int,
    is_freed: bool,
    free_count: int,  // How many times deferred for free
    reassignments: []string,  // History of reassignments
    scope_depth: int,  // Nesting level for scope analysis
}

// Scope-aware tracking
scope_stack: [dynamic]map[string]AllocationInfo
current_scope: map[string]AllocationInfo
```

### Algorithm Improvements
1. **Defer Counting**: Increment `free_count` for each defer free on same pointer
2. **Reassignment Detection**: Track when pointer is assigned new allocation
3. **Scope Analysis**: Push/pop scope contexts when entering/exiting blocks
4. **Cross-Referencing**: At end of scope, verify all allocations were freed exactly once

## 🎓 Conclusion

The test cases are working perfectly - they're exposing exactly where our implementation needs improvement. This is the power of test-driven development. The C002 rule has a solid foundation but needs significant enhancement to catch the comprehensive set of pointer safety issues that Odin developers should be protected from.