# C001 Rule Improvement Plan - Phase 2

## Overview
This plan addresses the critical bugs and architectural issues in the C001 rule implementation that are causing false positives, particularly in codebases with custom allocator patterns like RuiShin.

## Feedback Incorporation

Based on detailed analysis, we've identified 5 specific bugs and architectural issues:

1. **Bug 1**: "allocator" substring matching is too broad
2. **Bug 2**: Comma count heuristic is wrong  
3. **Bug 3**: File reading performance issue
4. **Bug 4**: Dual analysis path causing double reporting
5. **Bug 5**: Defer variable extraction returning function names instead of variables

## Implementation Plan

### Phase 1: Fix Critical Bugs (Priority Order)

#### Bug 5 - Fix Defer Variable Extraction (HIGHEST PRIORITY)
**Issue**: `extract_freed_var_name()` returns function names ("free", "delete") instead of actual variable names
**Impact**: Defer detection is completely broken - defers are never matched to allocations
**Fix**: Rewrite to return the actual variable being freed

**Implementation**:
```odin
// Current (broken):
extract_freed_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "call_expression" {
            for &grandchild in child.children {
                if grandchild.node_type == "identifier" {
                    return grandchild.text  // Returns "free" or "delete"!
                }
            }
        }
    }
    return ""
}

// Fixed:
extract_freed_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "call_expression" {
            found_callee := false
            for &grandchild in child.children {
                // Handle argument_list case
                if grandchild.node_type == "argument_list" {
                    for &arg in grandchild.children {
                        if arg.node_type == "identifier" {
                            return arg.text  // First arg = variable being freed
                        }
                    }
                }
                // Fallback for direct identifiers
                if grandchild.node_type == "identifier" {
                    if !found_callee {
                        found_callee = true  // Skip "free"/"delete"
                        continue
                    }
                    return grandchild.text  // Second identifier = variable
                }
            }
        }
    }
    return ""
}
```

**Validation**: Test with various defer patterns to ensure correct variable extraction

#### Bug 4 - Remove Dual Analysis Path
**Issue**: Two independent analysis paths causing double reporting and inconsistent results
**Impact**: Same allocations reported twice, some with wrong scope context
**Fix**: Remove the old scope-unaware path (lines 168-205)

**Implementation**:
- Remove lines 168-205 from `c001Matcher()`
- Keep only block-level analysis (path 1)
- Verify no legitimate violations are missed

**Validation**: Run full test suite to ensure no regression in detection

#### Bug 1 & 2 - Fix Allocator Detection
**Issue**: Too broad substring matching and wrong comma heuristic
**Impact**: Legitimate violations skipped, false negatives
**Fix**: Replace with precise allocator argument detection

**Implementation**:
```odin
// Replace current broad checks with:
has_allocator_arg :: proc(line: string) -> bool {
    // Find the opening paren of make( or new(
    make_start := strings.index(line, "make(")
    new_start  := strings.index(line, "new(")
    call_start := -1
    if make_start >= 0 do call_start = make_start + 4  // skip "make"
    if new_start  >= 0 do call_start = new_start  + 3  // skip "new"  
    if call_start < 0 do return false

    // Extract just the argument list
    args := line[call_start:]  // from "(" onward
    return strings.contains(args, "temp_allocator") ||
           strings.contains(args, ".allocator")     ||   // context.allocator, arena.allocator  
           strings.contains(args, "allocator)")          // named param at end
}

// Remove comma_count >= 3 heuristic entirely
// Replace with: if has_allocator_arg(line_content) { return true }
```

**Validation**: Test with various allocator patterns to ensure correct detection

#### Bug 3 - Optimize File Reading
**Issue**: File read on every allocation check
**Impact**: Performance degradation
**Fix**: Cache file content

**Implementation**:
- Pass file content as parameter to `uses_non_default_allocator()`
- Cache at `check_block_for_c001` level
- Read file once per block, not per allocation

**Validation**: Measure performance improvement

### Phase 2: Testing and Validation

#### Test Creation (Before Implementation)
- [ ] Create test cases for Bug 5 (defer variable extraction)
- [ ] Create test cases for Bug 4 (dual path removal)
- [ ] Create test cases for Bug 1/2 (allocator detection)
- [ ] Create test cases for Bug 3 (performance)

#### Validation Strategy
After each bug fix:
1. Run `/test/c001/` test suite
2. Test against Odin core libraries
3. Test against OLS codebase  
4. Test against RuiShin codebase
5. Verify false positive reduction
6. Check for new false negatives

### Phase 3: Documentation

- [ ] Update C001 rule documentation
- [ ] Explain conservative detection approach
- [ ] Document limitations and false positive/negative tradeoffs
- [ ] Add examples of detectable vs non-detectable patterns

## Expected Outcomes

1. **60-70% reduction in false positives** (primarily from Bug 5 fix)
2. **Improved detection accuracy** (from Bug 1/2 and Bug 4 fixes)
3. **Better performance** (from Bug 3 fix)
4. **More consistent results** (from removing dual analysis path)

## Success Criteria

✅ Bug 5: Defer detection works correctly - variables properly extracted
✅ Bug 4: No double reporting - each allocation reported once
✅ Bug 1/2: Legitimate violations no longer skipped incorrectly
✅ Bug 3: Performance improved - no redundant file reads
✅ All existing test cases still pass
✅ False positives significantly reduced across all codebases

## Implementation Order

1. **Bug 5** - Fix defer variable extraction (biggest impact)
2. **Bug 4** - Remove dual analysis path (eliminate doubles)
3. **Bug 1/2** - Fix allocator detection (reduce false negatives)
4. **Bug 3** - Optimize performance (cleanup)

## Validation Checkpoints

After each bug fix, pause for review and testing before proceeding to next.

---

**Approach**: Conservative detection with explicit suppression
**Priority**: Correctness over performance  
**Compatibility**: Safe to make breaking changes for accuracy
**Future**: RuiShin-specific handling will be separate improvement
