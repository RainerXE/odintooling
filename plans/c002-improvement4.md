# C002 Implementation Improvement Plan - Phase 4

## Critical Logic Issues

### 1. c002_markAsAllocated Write-Back Pattern (HIGH PRIORITY)
**Issue**: Write-back only happens when no double-free is found (lines 174–197)

**Current Code**:
```odin
if existing[i].free_count > 1 {
    return Diagnostic{ /* ... */ }  // ← Returns early, no write-back
}
// ...
ctx.allocations_map[var_name] = existing  // Only reached if no double-free
```

**Problem**: The write-back is only reached when no double-free is detected. While this works by accident (dynamic array backing memory is shared), it's fragile and breaks if heap-allocated fields are added.

**Fix**: Always write back before returning:
```odin
var diag_to_report: Diagnostic

if existing[i].free_count > 1 {
    diag_to_report = Diagnostic{ /* ... */ }
}

// Always write back the modified slice
ctx.allocations_map[var_name] = existing
return diag_to_report
```

**Location**: `src/core/c002-COR-Pointer.odin:174-197`

### 2. Multi-Assignment Handling (HIGH PRIORITY)
**Issue**: `extract_var_name_from_allocation` and `extract_var_name_from_assignment` fail on multi-assignment

**Current Code**:
```odin
parts := strings.split(text, "=")
if len(parts) >= 1 {
    var_name := strings.trim(parts[0], " \t")
    // For "a, b = make(...)", parts[0] = "a, b" which won't match allocations
}
```

**Fix**: Add multi-assignment detection and handling:
```odin
parts := strings.split(text, "=")
if len(parts) >= 1 {
    var_name := strings.trim(parts[0], " \t")
    
    // Handle multi-assignment: a, b = make(...)
    if strings.contains(var_name, ",") {
        // For now, take first variable and add comment about limitation
        // TODO: Track all variables in multi-assignment
        first_var := strings.trim(strings.split(var_name, ",")[0], " \t")
        return first_var
    }
    
    // Remove any type annotations
    if strings.contains(var_name, ":") {
        var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
    }
    return var_name
}
```

**Location**: `src/core/c002-COR-Pointer.odin:255, 305`

### 3. Scope Exit Detection (CRITICAL)
**Issue**: `is_entering_scope` and `is_scope_boundary` are now identical, causing scope counter drift

**Current Code**:
```odin
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block")
}

is_entering_scope :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block") && 
           strings.contains(node.text, "{")
}
```

**Problem**: Both functions check for "block" node type. The `is_entering_scope` check for `{` in text is unreliable because tree-sitter typically doesn't include `{` in block node text. This means scope counter will drift.

**Fix**: Track scope entry/exit properly:
```odin
// Track scope depth using a stack-based approach
C002AnalysisContext :: struct {
    // ... existing fields ...
    scope_stack: [dynamic]string,  // Track entered scopes
}

// Modified c002Matcher to handle scope entry/exit
if is_scope_boundary(node) {
    if is_entering_scope(node) {
        ctx.scope_stack = append(ctx.scope_stack, node.node_type)
        ctx.current_scope = len(ctx.scope_stack)
    } else {
        // Exiting scope - pop from stack
        if len(ctx.scope_stack) > 0 {
            ctx.scope_stack = ctx.scope_stack[0..<len(ctx.scope_stack)]
            ctx.current_scope = len(ctx.scope_stack)
        }
    }
}

// Helper functions
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block")
}

is_entering_scope :: proc(node: ^ASTNode) -> bool {
    // Use tree-sitter's entry/exit information if available,
    // or check for opening brace in text as fallback
    return strings.contains(node.node_type, "block")
}
```

**Location**: `src/core/c002-COR-Pointer.odin:270-280`

### 4. delete() Extraction Missing (MEDIUM)
**Issue**: `extract_var_name_from_free` doesn't handle `delete()` calls

**Current Code**:
```odin
// Pattern: defer free(variable)
if strings.contains(text, "free(") {
    // ... extraction logic ...
}
```

**Fix**: Add `delete()` extraction:
```odin
// Pattern: defer free(variable) or defer delete(variable)
if strings.contains(text, "free(") || strings.contains(text, "delete(") {
    var keyword: string
    if strings.contains(text, "free(") {
        keyword = "free"
    } else {
        keyword = "delete"
    }
    
    start_idx := strings.index(text, keyword + "(") + len(keyword) + 1
    // ... rest of extraction logic ...
}
```

**Location**: `src/core/c002-COR-Pointer.odin:208-221`

### 5. Pattern Matching Too Narrow (LOW)
**Issue**: `is_suspicious_pointer_usage` Pattern 1 (+)) never matches real code

**Current Code**:
```odin
if strings.contains(node.text, "+)") || strings.contains(node.text, "-)") {
    return true
}
```

**Fix**: Make pattern more robust:
```odin
// Pattern: Complex expressions in free (often wrong)
// Check for arithmetic operations before the closing paren
if strings.contains(node.text, "+ ") || strings.contains(node.text, "- ") ||
   strings.contains(node.text, "* ") || strings.contains(node.text, "/ ") {
    return true
}
```

**Location**: `src/core/c002-COR-Pointer.odin:307-309`

### 6. Map Key Existence Check (MEDIUM)
**Issue**: `c002_markAsAllocated` uses `len == 0` instead of `not_in` guard

**Current Code**:
```odin
existing := ctx.allocations_map[var_name]
if len(existing) == 0 {
    existing = make([dynamic]C002AllocationInfo)
}
```

**Fix**: Use proper existence check:
```odin
if var_name not_in ctx.allocations_map {
    ctx.allocations_map[var_name] = make([dynamic]C002AllocationInfo)
}
existing := ctx.allocations_map[var_name]
```

**Location**: `src/core/c002-COR-Pointer.odin:163-168`

## Minor/Cosmetic Issues

### 7. Dead Code Removal
**Issue**: `is_cleanup_function` is defined but never called

**Fix**: Remove unused function or wire it in properly.

**Location**: `src/core/c002-COR-Pointer.odin:52`

### 8. Registry Nil Risk
**Issue**: `C002Rule` registers `matcher = nil` which could cause panics

**Fix**: Either don't register C002 in registry, or add nil guard:
```odin
// Option 1: Don't register (recommended since called directly)
// Remove C002Rule() call from registerRule

// Option 2: Add nil guard in registry usage
if rule.matcher != nil {
    diag := rule.matcher(file_path, node)
}
```

**Location**: `src/core/c002-COR-Pointer.odin:46`

### 9. Message Consistency
**Issue**: Inconsistent message formatting between diagnostics

**Fix**: Standardize on one format (recommend without prefix since rule ID is in struct):
```odin
// Change from:
message = "C002 [correctness] Freeing reassigned pointer"
// To:
message = "Freeing reassigned pointer"
```

**Locations**: `src/core/c002-COR-Pointer.odin:108, 122`

## Implementation Plan

### Phase 1: Critical Fixes
1. Fix c002_markAsAllocated write-back pattern
2. Fix scope exit detection (most critical issue)
3. Add delete() extraction support
4. Fix multi-assignment handling

### Phase 2: Medium Priority
1. Fix map key existence check
2. Improve pattern matching robustness
3. Remove dead code
4. Address registry nil risk

### Phase 3: Cosmetic/Quality
1. Standardize message formatting
2. Add comprehensive comments
3. Update documentation

## Priority Order

1. **CRITICAL**: Scope exit detection (currently broken)
2. **HIGH**: Write-back pattern, multi-assignment, delete() support
3. **MEDIUM**: Map key check, pattern matching, dead code
4. **LOW**: Message consistency, documentation

## Expected Outcome

After implementation:
- ✅ Correct scope tracking (no counter drift)
- ✅ Proper write-back semantics (no memory leaks)
- ✅ Complete delete() support
- ✅ Multi-assignment handling
- ✅ Robust pattern matching
- ✅ Clean codebase (no dead code)
- ✅ Consistent diagnostics