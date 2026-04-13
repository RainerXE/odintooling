# C002 Improvement Phase 14 - Final Polish

## 🎯 Objective
Address remaining issues and polish C002 for production deployment.

## 🚨 Critical Issues

### Bug 1: Memory Leak in File Reading
**Problem**: `owned_content` and `owned_lines` are never freed.

**Location**: `src/core/c002-COR-Pointer.odin` lines 57-62

**Fix**: Add defer cleanup immediately after allocation
```odin
if len(lines) == 0 {
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil do return {}
    owned_content = content
    owned_lines = strings.split(string(content), "\n")
    lines = owned_lines
    defer {
        delete(owned_lines)
        delete(owned_content)
    }
}
```

**Impact**: Prevents memory leak on every file analysis

### Bug 2: File Re-Reading in Recursive Calls
**Problem**: Recursive calls don't pass `lines`, causing file re-reads

**Location**: `src/core/c002-COR-Pointer.odin` line 173

**Fix**: Pass `lines` to recursive calls
```odin
for &child in node.children {
    child_diagnostics := c002Matcher(file_path, &child, ctx, lines)
}
```

**Impact**: Improves performance by reading file once per analysis

### Bug 3: fmt.tprintf Temp Allocator Issue
**Problem**: `fmt.tprintf` uses temp allocator, creating dangling references

**Location**: `src/core/c002-COR-Pointer.odin` line 258

**Fix**: Use `fmt.aprintf` with proper allocator
```odin
fix = fmt.aprintf("Allocation at line %d,%d freed %d times",
                existing[i].line, existing[i].col, existing[i].free_count),
```

**Impact**: Prevents dangling string references

### Bug 4: Unreliable .text in is_defer_cleanup
**Problem**: Uses `gc.text` which may be empty in tree-sitter

**Location**: `src/core/c002-COR-Pointer.odin` lines 295-297

**Fix**: Use file_lines for reliable text extraction
```odin
if gc.node_type == "identifier" {
    line_idx := gc.start_line - 1
    if line_idx < len(lines) {
        line := lines[line_idx]
        col := gc.start_column - 1
        if col >= 0 && col < len(line) {
            rest := line[col:]
            if strings.has_prefix(rest, "free(") || strings.has_prefix(rest, "delete(") {
                // Found free/delete
            }
        }
    }
}
```

**Impact**: Makes defer detection reliable

## 🟠 High Priority Fixes

### Bug 5: Scope Stack Uses Generic "block" Strings
**Problem**: Scope stack stores "block" instead of unique identifiers

**Location**: `src/core/c002-COR-Pointer.odin` line 60

**Impact**: Only affects depth counting (current use case), but worth noting

### Bug 6: free_count Increments First Match
**Problem**: Increments first scope <= current, not innermost scope

**Location**: `src/core/c002-COR-Pointer.odin` line 242

**Fix**: Find innermost matching scope
```odin
best_match := -1
for i in 0..<len(existing) {
    if existing[i].scope_level <= scope_level {
        if best_match == -1 || existing[i].scope_level > existing[best_match].scope_level {
            best_match = i
        }
    }
}
if best_match >= 0 {
    existing[best_match].free_count += 1
    // ... report logic
}
```

**Impact**: More accurate double-free detection with scope shadowing

### Bug 7: Outdated Proc Comment
**Problem**: Proc comment not updated after rule rename

**Location**: `src/core/c002-COR-Pointer.odin` line 54

**Fix**: Update comment
```odin
// c002Matcher checks for double-free patterns
```

**Impact**: Documentation accuracy

### Bug 8: Redundant Tree Traversals
**Problem**: `is_defer_cleanup` and `extract_var_name_from_free` both traverse same nodes

**Impact**: Minor performance optimization opportunity

## 📅 Timeline & Priority

### Critical Fixes (Do Immediately)
1. Memory leak in file reading - **HIGH**
2. File re-reading in recursive calls - **HIGH**
3. fmt.tprintf temp allocator - **HIGH**
4. Unreliable .text in is_defer_cleanup - **HIGH**

**Estimated**: 2-3 hours

### High Priority Fixes (Do Next)
5. Scope stack strings - **LOW** (documentation only)
6. free_count scope matching - **MEDIUM**
7. Proc comment - **LOW** (documentation only)
8. Redundant traversals - **LOW** (optimization)

**Estimated**: 1-2 hours

## ✅ Success Criteria

### After Fixes
- ✅ No memory leaks
- ✅ Single file read per analysis
- ✅ No dangling string references
- ✅ Reliable defer detection
- ✅ Accurate scope matching
- ✅ Clean documentation

## 🎯 Expected Outcome

**Production-ready C002 rule that:**
- Detects double-free patterns reliably
- Works efficiently on large codebases
- No memory leaks or crashes
- Zero false positives
- Clean, maintainable code

**Status**: Resolution plan created - ready for implementation! 🚀