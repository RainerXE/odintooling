# C002 Implementation Fix Plan - Phase 5

## Critical Bugs

### 1. Scope Tracking Completely Broken (CRITICAL)
**Issue**: `is_entering_scope` and `is_scope_boundary` are identical, causing scope counter to only increase

**Current Code**:
```odin
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block")
}

is_entering_scope :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block")
}
```

**Problem**: Both functions return true for block nodes, so `is_entering_scope` always returns true. The else branch (scope exit) is unreachable. Scope level only increases, never decreases.

**Fix**: Use pre-order/post-order traversal:
```odin
// Replace current scope tracking with:
is_block := strings.contains(node.node_type, "block")

if is_block {
    // Entering scope - push before processing children
    ctx.scope_stack = append(ctx.scope_stack, node.node_type)
    ctx.current_scope = len(ctx.scope_stack)
}

// ... all allocation/free checks ...

// Recurse into children
for &child in node.children {
    child_diagnostics := c002Matcher(file_path, &child, ctx)
    // collect diagnostics...
}

// After children: exit scope
if is_block {
    if len(ctx.scope_stack) > 0 {
        ctx.scope_stack = ctx.scope_stack[0..<len(ctx.scope_stack)-1]  // Proper pop
    }
    ctx.current_scope = len(ctx.scope_stack)
}
```

**Impact**: This makes `is_scope_boundary` and `is_entering_scope` unnecessary - delete them.

**Location**: `src/core/c002-COR-Pointer.odin:299-310, 68-74`

### 2. Scope Stack Pop is No-Op (CRITICAL)
**Issue**: `ctx.scope_stack[0..<len(ctx.scope_stack)]` returns full slice unchanged

**Current Code**:
```odin
ctx.scope_stack = ctx.scope_stack[0..<len(ctx.scope_stack)]  // Wrong!
```

**Fix**: Use proper slice or pop:
```odin
// Option 1: Proper slice
ctx.scope_stack = ctx.scope_stack[0:len(ctx.scope_stack)-1]

// Option 2: Use Odin's pop (better)
pop(&ctx.scope_stack)
```

**Location**: `src/core/c002-COR-Pointer.odin:72`

### 3. Invalid Odin Syntax (BLOCKER)
**Issue**: `var diag_to_report: Diagnostic` uses `var` keyword which doesn't exist in Odin

**Current Code**:
```odin
var diag_to_report: Diagnostic  // WRONG - var is not Odin syntax
```

**Fix**: Remove `var` keyword:
```odin
diag_to_report: Diagnostic  // CORRECT Odin syntax
```

**Location**: `src/core/c002-COR-Pointer.odin:183`

### 4. Unused Import (COMPILATION ERROR)
**Issue**: `import "core:os"` is unused

**Fix**: Remove unused import or add usage.

**Location**: `src/core/c002-COR-Pointer.odin:4`

## Logic Issues

### 5. Allocation Tracking Silently Fails (HIGH PRIORITY)
**Issue**: `extract_var_name_from_allocation` looks for `:=` in call_expression node text

**Problem**: call_expression node text is just `make(...)` not `buf := make(...)`. The function returns empty string, so allocations are never tracked.

**Fix**: Detect allocation on assignment/declaration nodes:
```odin
// Change is_pointer_allocation to match nodes containing both LHS and RHS
is_pointer_allocation :: proc(node: ^ASTNode) -> bool {
    return (strings.contains(node.node_type, "short_var_declaration") ||
            strings.contains(node.node_type, "assignment")) &&
           (strings.contains(node.text, "make(") || 
            strings.contains(node.text, "new(") ||
            strings.contains(node.text, "alloc(") ||
            strings.contains(node.text, "malloc("))
}

// extract_var_name_from_allocation now works on the full statement
```

**Location**: `src/core/c002-COR-Pointer.odin:248-254, 260-280`

### 6. Potential Duplicate Allocation Tracking (MEDIUM)
**Issue**: `is_pointer_allocation` may match ancestor nodes

**Problem**: If tree-sitter includes full statement text in parent nodes, same allocation could be registered multiple times.

**Fix**: Add debugging and validation:
```odin
// Add AST dump debugging to verify what nodes contain "make("
// Consider adding visited set to prevent duplicate registration
```

**Location**: `src/core/c002-COR-Pointer.odin:248-254`

### 7. Pattern Matching Too Broad (LOW)
**Issue**: Pattern 1 fires on arithmetic anywhere in node text

**Current Code**:
```odin
if strings.contains(node.text, "+ ") || strings.contains(node.text, "- ") {
    return true
}
```

**Fix**: Check only extracted variable region:
```odin
// Extract variable name first, then check that specific region
var_name := extract_var_name_from_free(node)
if var_name != "" {
    var_region := get_variable_region(node.text, var_name)
    if strings.contains(var_region, "+ ") || strings.contains(var_region, "- ") {
        return true
    }
}
```

**Location**: `src/core/c002-COR-Pointer.odin:360-362`

### 8. Multiple Double-Free Detection (LOW)
**Issue**: Only first double-free per call is reported

**Current Code**: Returns single Diagnostic, but could return []Diagnostic

**Fix**: Consider returning []Diagnostic for completeness:
```odin
c002_markAsFreed :: proc(/*...*/) -> []Diagnostic {
    var diagnostics: [dynamic]Diagnostic
    // ... detection logic ...
    if existing[i].free_count > 1 {
        diagnostics = append(diagnostics, Diagnostic{/*...*/})
    }
    return diagnostics[:]
}
```

**Location**: `src/core/c002-COR-Pointer.odin:174-197`

## Implementation Plan

### Phase 1: Fix Compilation Errors (BLOCKER)
1. Fix `var diag_to_report` → `diag_to_report` (line 183)
2. Remove unused `import "core:os"` (line 4)
3. Test compilation

### Phase 2: Fix Critical Logic Bugs
1. Replace scope tracking with pre-order/post-order approach
2. Fix scope stack pop operation
3. Delete `is_scope_boundary` and `is_entering_scope` functions
4. Test scope tracking works correctly

### Phase 3: Fix Allocation Tracking
1. Fix `extract_var_name_from_allocation` to work on assignment nodes
2. Update `is_pointer_allocation` to match correct node types
3. Add debugging to verify allocation detection
4. Test allocation tracking works

### Phase 4: Improve Robustness
1. Add duplicate allocation prevention
2. Narrow pattern matching to variable region
3. Consider []Diagnostic return for multiple double-frees

## Priority Order

1. **BLOCKER**: Fix compilation errors (syntax, unused import)
2. **CRITICAL**: Fix scope tracking (currently broken)
3. **HIGH**: Fix allocation tracking (silently failing)
4. **MEDIUM**: Prevent duplicates, improve patterns
5. **LOW**: Multiple double-free reporting

## Expected Outcome

After implementation:
- ✅ Compiles without errors
- ✅ Scope tracking works correctly (increases and decreases)
- ✅ Allocations are properly tracked
- ✅ No duplicate registrations
- ✅ Precise pattern matching
- ✅ Robust error handling