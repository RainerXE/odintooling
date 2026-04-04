# C002 Implementation Fix Plan - Phase 3

## Critical Compilation Issues (BLOCKER)

### 1. Dynamic Array Declaration Syntax
**Issue**: `var diagnostics: []Diagnostic` is invalid Odin syntax (line 58)

**Fix**: Use proper dynamic array declaration:
```odin
// WRONG:
var diagnostics: []Diagnostic

// CORRECT:
diagnostics: [dynamic]Diagnostic
```

**Location**: `src/core/c002-COR-Pointer.odin:58`

### 2. strings.index with Start Position
**Issue**: `strings.index(text, ")", start_idx)` doesn't exist in core:strings

**Fix**: Slice the string first:
```odin
// WRONG:
end_idx := strings.index(text, ")", start_idx)

// CORRECT:
rest := text[start_idx:]
rel := strings.index(rest, ")")
end_idx := start_idx + rel  // if rel >= 0
```

**Location**: `src/core/c002-COR-Pointer.odin:202`

### 3. Slice Syntax Error
**Issue**: `text[start_idx..=end_idx]` uses wrong syntax

**Fix**: Use Odin's `[lo:hi]` syntax:
```odin
// WRONG:
var_name := strings.trim(text[start_idx..=end_idx], " \t")

// CORRECT:
var_name := strings.trim(text[start_idx:end_idx], " \t")
```

**Location**: `src/core/c002-COR-Pointer.odin:204`

### 4. os.read_entire_file_from_path Error Handling
**Issue**: Wrong return type check in `main.odin`

**Fix**: Update error handling:
```odin
// WRONG:
content, err := os.read_entire_file_from_path(file_path)
if err != nil { /* ... */ }

// CORRECT:
content, ok := os.read_entire_file_from_path(file_path)
if !ok { /* ... */ }
```

**Location**: `src/core/main.odin:148`

## Architecture Issues

### 5. Procedure Signature Mismatch
**Issue**: `c002Matcher` signature doesn't match `Rule.matcher` field type

**Current State**:
```odin
// c002Matcher signature:
c002Matcher :: proc(file_path: string, node: ^ASTNode, ctx: ^C002AnalysisContext) -> []Diagnostic

// Rule.matcher field type:
matcher: proc(file_path: string, node: ^ASTNode) -> Diagnostic
```

**Solution**: Remove `c002Matcher` from `Rule` struct and call directly:
```odin
// In main.odin, replace:
// c002_rule.matcher(file_path, &ast_root, &c002_ctx)

// With direct call:
c002_diagnostics := c002Matcher(file_path, &ast_root, &c002_ctx)
```

**Locations**:
- `src/core/c002-COR-Pointer.odin:57` (signature)
- `src/core/main.odin:266` (call site)
- `src/core/main.odin:46` (Rule struct definition)

### 6. Dynamic Array Append Pattern
**Issue**: Appending to nil dynamic array in map value

**Current Code**:
```odin
ctx.allocations_map[var_name] = append(ctx.allocations_map[var_name], allocation)
```

**Improved Pattern**:
```odin
// Check if key exists and initialize if not
existing := ctx.allocations_map[var_name]
if len(existing) == 0 {
    existing = make([dynamic]C002AllocationInfo)
}
existing = append(existing, allocation)
ctx.allocations_map[var_name] = existing
```

**Location**: `src/core/c002-COR-Pointer.odin:160`

## Logic Issues

### 7. Redundant Pattern in is_suspicious_pointer_usage
**Issue**: Pattern 3 (reassignment detection) duplicates ctx.reassignments check

**Current Code**:
```odin
// Pattern 3: Reassignment before free (common mistake)
if strings.contains(node.text, "=") && strings.contains(node.text, "free") {
    return true
}
```

**Fix**: Remove Pattern 3 entirely since reassignment is already tracked via `ctx.reassignments` and checked separately.

**Location**: `src/core/c002-COR-Pointer.odin:329`

### 8. Incomplete extract_var_name_from_allocation
**Issue**: Only handles `:=` but not `=` assignments

**Current Code**:
```odin
} else if strings.contains(text, "=") {
    // Handle variable = make(...) pattern
    // This is more complex - need to find the assignment target
    // For now, return empty to be conservative
    return ""
}
```

**Fix**: Implement proper `=` assignment handling:
```odin
} else if strings.contains(text, "=") {
    // Handle variable = make(...) pattern
    // Look for the assignment target before the =
    if strings.contains(text, "=") {
        parts := strings.split(text, "=")
        if len(parts) >= 1 {
            var_name := strings.trim(parts[0], " \t")
            // Remove any type annotations
            if strings.contains(var_name, ":") {
                var_name = strings.trim(strings.split(var_name, ":")[0], " \t")
            }
            return var_name
        }
    }
}
```

**Location**: `src/core/c002-COR-Pointer.odin:242-244`

### 9. Overly Broad Reassignment Detection
**Issue**: `is_pointer_reassignment` matches `!=` and `==`

**Current Code**:
```odin
return strings.contains(node.node_type, "assignment") &&
       strings.contains(node.text, "=") &&
       !strings.contains(node.text, ":=")
```

**Fix**: Rely on node type alone:
```odin
// Since we're already checking node_type contains "assignment",
// the text check is redundant and can cause false positives
return strings.contains(node.node_type, "assignment")
```

**Location**: `src/core/c002-COR-Pointer.odin:275`

### 10. Scope Counter Double-Increment
**Issue**: Proc bodies increment scope counter twice

**Current Code**:
```odin
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "block") ||
           strings.contains(node.node_type, "proc") ||
           strings.contains(node.node_type, "for") ||
           strings.contains(node.node_type, "if") ||
           strings.contains(node.node_type, "case")
}
```

**Fix**: Track scope only on block nodes:
```odin
is_scope_boundary :: proc(node: ^ASTNode) -> bool {
    // Only track actual scope containers (blocks)
    return strings.contains(node.node_type, "block")
}

is_entering_scope :: proc(node: ^ASTNode) -> bool {
    // For blocks, we're entering when we see the opening brace
    return strings.contains(node.node_type, "block") && 
           strings.contains(node.text, "{")
}
```

**Location**: `src/core/c002-COR-Pointer.odin:260-268`

### 11. Missing File Field in Diagnostic
**Issue**: `c002_markAsFreed` returns diagnostic with empty file field

**Current Code**:
```odin
return Diagnostic{
    file = "",  // ← Empty file field
    line = line,
    column = col,
    // ...
}
```

**Fix**: Pass file path from caller:
```odin
// Update signature to accept file_path
c002_markAsFreed :: proc(var_name: string, line: int, col: int, scope_level: int, file_path: string, ctx: ^C002AnalysisContext) -> Diagnostic {
    // ...
    return Diagnostic{
        file = file_path,  // ← Use passed file path
        line = line,
        column = col,
        // ...
    }
}

// Update call site to pass file_path
diag := c002_markAsFreed(var_name, node.start_line, node.start_column, ctx.current_scope, file_path, ctx)
```

**Locations**:
- `src/core/c002-COR-Pointer.odin:175` (signature)
- `src/core/c002-COR-Pointer.odin:119` (call site)

## Implementation Plan

### Phase 1: Fix Compilation Errors (BLOCKER)
1. Fix `var diagnostics` → `diagnostics: [dynamic]Diagnostic`
2. Fix `strings.index` with start position
3. Fix slice syntax `..=` → `:`
4. Fix `os.read_entire_file_from_path` error handling
5. Test compilation

### Phase 2: Fix Architecture Issues
1. Decouple `c002Matcher` from `Rule.matcher` field
2. Update `main.odin` to call `c002Matcher` directly
3. Fix dynamic array append pattern in `c002_markAsAllocated`
4. Test functionality

### Phase 3: Fix Logic Issues
1. Remove redundant Pattern 3 from `is_suspicious_pointer_usage`
2. Implement `=` assignment handling in `extract_var_name_from_allocation`
3. Fix `is_pointer_reassignment` to avoid false positives
4. Fix scope tracking to only use block nodes
5. Add file field to double-free diagnostic

### Phase 4: Testing and Validation
1. Run comprehensive test suite
2. Validate no false positives
3. Confirm all real issues detected
4. Performance testing

## Priority Order

1. **BLOCKER**: Fix compilation errors (syntax, API calls)
2. **HIGH**: Fix architecture issues (signature mismatch)
3. **MEDIUM**: Fix logic issues (false positives, missing features)
4. **LOW**: Optimize and clean up

## Expected Outcome

After implementation:
- ✅ Compiles without errors
- ✅ Correct procedure signatures
- ✅ No false positives from improved logic
- ✅ Complete assignment handling (= and :=)
- ✅ Accurate scope tracking
- ✅ Proper error handling
- ✅ Clean diagnostics with file paths