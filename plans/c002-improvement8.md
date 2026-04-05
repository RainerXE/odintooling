# C002 Improvement Plan - Phase 8: False Positive Suppression Fix

## Problem Analysis

The current C002 implementation has critical issues with false positive suppression:

### 1. Ineffective Suppressors (5/6 never fire or are dead code)
- `is_enhanced_allocator_pattern`: Overly broad name matching suppresses real violations
- `is_temporary_allocation`: "100)" check is ineffective and arbitrary
- `is_in_loop_context`: Never fires due to incorrect node.text checking
- `is_string_processing_pattern`: Never fires on defer_statement nodes
- `is_complex_expression`: Never triggers on defer_statement nodes

### 2. Structural Logic Bugs
- `is_scope_boundary` and `is_entering_scope` are identical
- Scope counter only increases, never decreases properly
- `found_definite_violation` flag is set too late to be effective
- `is_clear_double_free` checks free_count before it's incremented

### 3. Wrong Detection Approach
- Pattern 3 in `is_definite_pointer_misuse` can never fire
- Allocation tracking fails because it matches call_expression instead of assignment nodes

## Solution Strategy

### Phase 1: Remove Ineffective Suppressors
**Action**: Replace entire suppression block with single allocation tracking gate
```odin
// Replace lines 109-143 with:
if var_name not_in ctx.allocations_map {
    // Skip silently - we didn't see the allocation
    continue
}
```

### Phase 2: Fix Structural Logic Bugs
**Action**: Fix scope tracking and detection order
```odin
// Fix scope tracking (lines 377-388)
is_block := strings.contains(node.node_type, "block")
if is_block {
    append(&ctx.scope_stack, node.node_type)
    ctx.current_scope = len(ctx.scope_stack)
}
// ... checks ...
for &child in node.children { ... }
// after children:
if is_block && len(ctx.scope_stack) > 0 {
    pop(&ctx.scope_stack)
    ctx.current_scope = len(ctx.scope_stack)
}
```

### Phase 3: Fix Allocation Tracking
**Action**: Match assignment/declaration nodes instead of call_expression
```odin
// Change is_pointer_allocation to match assignment nodes
is_pointer_allocation :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.node_type, "assignment") ||
           strings.contains(node.node_type, "declaration")
}
```

### Phase 4: Implement Precise Detection Logic
**Action**: Use three clear cases based on tracked state
```odin
// Detection logic becomes:
if var_name not_in ctx.allocations_map {
    // Skip - no allocation record
    continue
}

diag := c002_markAsFreed(var_name, line, col, scope_level, file_path, ctx)
if diag.message != "" {
    // Double free detected - definite violation
    append(&diagnostics, diag)
    continue
}

allocation_info := ctx.allocations_map[var_name][0]
if allocation_info.is_reassigned {
    // Potential misuse - contextual
    append(&diagnostics, create_contextual_diagnostic(...))
}
```

## Implementation Plan

1. **Remove suppressors** (lines 109-143, 500-594)
2. **Fix scope tracking** (lines 377-388, 69)
3. **Fix allocation tracking** (line 327)
4. **Remove dead code** (Pattern 3 in is_definite_pointer_misuse)
5. **Simplify detection logic** to 3 clear cases

## Validation Criteria

- ✅ No false positives on valid code
- ✅ All real violations still detected
- ✅ Test suite passes with 26+ violations
- ✅ No dead code or ineffective suppressors
