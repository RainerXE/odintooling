# C002 Improvement Phase 13 - Critical Bug Fixes

## 🎯 Objective
Fix critical bugs in C002 implementation that prevent it from working correctly in production.

## 🚨 Critical Issues Summary

### **Blockers (Rule Currently Has Serious Bugs)**
1. **Nil map initialization** - `create_c002_context` creates nil maps that panic on write
2. **Callee text reliance** - Still uses unreliable `node.text` for make/new detection
3. **Scope comparison bug** - Misses cross-scope double-frees (too strict)
4. **Memory leaks** - Proc boundary reset leaks dynamic slices
5. **Temp allocator issue** - `fmt.tprintf` creates dangling string references

### **High Priority Issues**
6. **Non-Odin functions** - Still checks for `alloc`/`malloc` (not Odin builtins)
7. **Index expression handling** - Doesn't skip `buf[i] =` patterns correctly
8. **Reassignment scope bug** - Marks all scope entries instead of current scope

### **Medium Priority Issues**
9. **Missing file caching** - Needed for callee text fix
10. **No cleanup function** - Caller can't free memory properly

## 🔧 Resolution Plan

### Phase 1: Fix Critical Blockers (Do Immediately)

#### **1. Fix nil map initialization**
**Problem**: `create_c002_context` uses `{}` which creates nil maps.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~30):
```odin
// Before (BROKEN)
create_c002_context :: proc() -> C002AnalysisContext {
    return C002AnalysisContext{
        allocations_map = {},   // ❌ nil map - will panic
        current_scope = 0,
        scope_stack = {},       // ❌ nil dynamic array
    }
}

// After (FIXED)
create_c002_context :: proc() -> C002AnalysisContext {
    return C002AnalysisContext{
        allocations_map = make(map[string][dynamic]C002AllocationInfo),
        current_scope = 0,
        scope_stack = make([dynamic]string),
    }
}
```

**Files**: `src/core/c002-COR-Pointer.odin`
**Impact**: Prevents runtime panics

#### **2. Fix callee.text reliance using file_lines**
**Problem**: Uses unreliable `node.text` for make/new detection.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~90):
```odin
// Before (BROKEN)
callee_text := ""
if callee.node_type == "identifier" {
    callee_text = callee.text  // ❌ unreliable
}
if callee_text == "make" || callee_text == "new" || ...

// After (FIXED)
// Add file_lines parameter to c002Matcher
c002Matcher :: proc(file_path: string, node: ^ASTNode, ctx: ^C002AnalysisContext, file_lines: []string) -> []Diagnostic {
    ...
    
    // Use file_lines for reliable text extraction
    if callee.start_line > 0 && callee.start_line - 1 < len(file_lines) {
        line := file_lines[callee.start_line - 1]
        col := callee.start_column - 1
        if col >= 0 && col < len(line) {
            rest := line[col:]
            if strings.has_prefix(rest, "make(") || strings.has_prefix(rest, "new(") {
                // ✅ Reliable detection
            }
        }
    }
}
```

**Files**: 
- `src/core/c002-COR-Pointer.odin` - Add file_lines parameter
- `src/core/main.odin` - Pass file_lines from main matcher
**Impact**: Makes allocation detection reliable

#### **3. Fix scope comparison for cross-scope double-frees**
**Problem**: Scope check uses `==` instead of `<=`, misses cross-scope doubles.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~220):
```odin
// Before (BROKEN)
if existing[i].scope_level == scope_level {  // ❌ Too strict
    existing[i].free_count += 1
}

// After (FIXED)
if existing[i].scope_level <= scope_level {  // ✅ Allow cross-scope
    existing[i].free_count += 1
}
```

**Impact**: Detects double-frees across nested scopes

#### **4. Fix memory leak in proc boundary reset**
**Problem**: Old allocations_map values leaked when resetting at proc boundaries.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~70):
```odin
// Before (BROKEN)
if is_proc {
    ctx.allocations_map = make(map[string][dynamic]C002AllocationInfo)  // ❌ Leaks old map
    ctx.scope_stack = make([dynamic]string)
}

// After (FIXED)
if is_proc {
    // Free old allocations first
    for _, &v in ctx.allocations_map do delete(v)
    delete(ctx.allocations_map)
    delete(ctx.scope_stack)
    
    // Create new structures
    ctx.allocations_map = make(map[string][dynamic]C002AllocationInfo)
    ctx.scope_stack = make([dynamic]string)
    ctx.current_scope = 0
}
```

**Impact**: Prevents memory leaks

#### **5. Fix fmt.tprintf temp allocator issue**
**Problem**: Uses temp allocator, creates dangling string references.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~225):
```odin
// Before (BROKEN)
fix = fmt.tprintf("Allocation at line %d,%d freed %d times", ...)

// After (FIXED)
fix = fmt.aprintf(context.allocator, "Allocation at line %d,%d freed %d times", ...)
// Caller must free the string when done
```

**Impact**: Prevents dangling references

### Phase 2: High Priority Fixes

#### **6. Remove non-Odin alloc/malloc checks**
**Problem**: Checks for non-Odin functions `alloc`/`malloc`.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~95):
```odin
// Before (WRONG)
if callee_text == "make" || callee_text == "new" || 
   callee_text == "alloc" || callee_text == "malloc" {

// After (FIXED)
if callee_text == "make" || callee_text == "new" {
```

**Impact**: Prevents false positives

#### **7. Fix extract_lhs_var_name to skip index_expression**
**Problem**: Doesn't handle `buf[i] =` patterns correctly.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~290):
```odin
// Before (INCOMPLETE)
extract_lhs_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        if child.node_type == "identifier" do return child.text
    }
    return ""
}

// After (FIXED)
extract_lhs_var_name :: proc(node: ^ASTNode) -> string {
    for &child in node.children {
        // Skip LHS expressions that aren't plain variable names
        if child.node_type == "selector_expression" ||
           child.node_type == "index_expression" {
            return ""
        }
        if child.node_type == "identifier" do return child.text
    }
    return ""
}
```

**Impact**: Prevents incorrect tracking

#### **8. Fix reassignment to only mark current scope**
**Problem**: Marks all scope entries instead of just current scope.

**Fix** (`src/core/c002-COR-Pointer.odin` line ~120):
```odin
// Before (WRONG)
for i in 0..<len(existing) {
    existing[i].is_reassigned = true  // ❌ Marks ALL entries
}

// After (FIXED)
for i in 0..<len(existing) {
    if existing[i].scope_level == ctx.current_scope {  // ✅ Only current scope
        existing[i].is_reassigned = true
        existing[i].reassignment_line = node.start_line
    }
}
```

**Impact**: More accurate reassignment tracking

### Phase 3: Medium Priority Fixes

#### **9. Add file_lines caching like C001**
**Problem**: No file caching for text extraction.

**Fix**: Add to `C002AnalysisContext` and initialize in `c002Matcher`:
```odin
// Add to context struct
file_lines: []string
file_path: string

// Initialize in c002Matcher
if file_path != ctx.file_path {
    ctx.file_lines = strings.split(read_file(file_path), "\n")
    ctx.file_path = file_path
}
```

**Files**: `src/core/c002-COR-Pointer.odin`
**Impact**: Enables reliable text extraction

#### **10. Add destroy_c002_context for cleanup**
**Problem**: No way to clean up memory after analysis.

**Fix**: Add cleanup function:
```odin
destroy_c002_context :: proc(ctx: ^C002AnalysisContext) {
    for _, &v in ctx.allocations_map do delete(v)
    delete(ctx.allocations_map)
    delete(ctx.scope_stack)
}
```

**Impact**: Proper memory management

## 📅 Timeline & Priority

### **Critical Fixes (Do Immediately - Rule Broken)**
1. Fix nil map initialization - **HIGH** (30 min)
2. Fix callee.text reliance - **HIGH** (1 hour)
3. Fix scope comparison - **HIGH** (30 min)
4. Fix memory leaks - **HIGH** (30 min)
5. Fix fmt.tprintf - **HIGH** (30 min)

**Estimated**: 3-4 hours

### **High Priority Fixes (Do Next - Improve Quality)**
6. Remove alloc/malloc - **MEDIUM** (15 min)
7. Fix index_expression - **MEDIUM** (30 min)
8. Fix reassignment scope - **MEDIUM** (30 min)

**Estimated**: 1-2 hours

### **Medium Priority Fixes (Do After - Polish)**
9. Add file caching - **MEDIUM** (1 hour)
10. Add cleanup function - **LOW** (30 min)

**Estimated**: 1-2 hours

## ✅ Success Criteria

### **Phase 1 Complete**
- ✅ No runtime panics (nil map fix)
- ✅ Reliable allocation detection (callee.text fix)
- ✅ Cross-scope double-frees detected (scope fix)
- ✅ No memory leaks (proc reset fix)
- ✅ No dangling references (fmt.tprintf fix)

### **Phase 2 Complete**
- ✅ No false positives (alloc/malloc removal)
- ✅ Correct LHS extraction (index_expression fix)
- ✅ Accurate reassignment tracking (scope-specific marking)

### **Phase 3 Complete**
- ✅ Efficient file handling (file caching)
- ✅ Proper memory management (cleanup function)

## 🎯 Expected Outcome

After completing this plan:
- **C002 works reliably** on all real code (currently has critical bugs)
- **No false positives** on clean code
- **No memory leaks** or crashes
- **Accurate detection** of double-free patterns
- **Production-ready** quality

## 🔧 Implementation Strategy

### **Incremental Testing**
1. Fix nil maps → Test basic functionality
2. Fix callee detection → Test allocation tracking
3. Fix scope comparison → Test nested scopes
4. Fix memory leaks → Test multiple procedures

### **Validation Plan**
- Test on Odin core libraries
- Test on RuiShin production code
- Test on OLS codebase
- Verify no false positives
- Verify correct detection of double-frees

## 📝 Test Cases to Add

### **Test Case 1: Nil Map Panic Prevention**
```odin
// Should not panic
proc test_many_procs() {
    for i in 0..<100 {
        test_proc()  // Each proc resets context
    }
}
```

### **Test Case 2: Cross-Scope Double-Free**
```odin
proc test_cross_scope() {
    buf := make([]u8, 100)  // Scope 1
    defer free(buf)
    
    if true {
        defer free(buf)  // Scope 2 - should detect
    }
}
```

### **Test Case 3: Index Expression Safety**
```odin
proc test_index_expression() {
    buf := make([]u8, 100)
    buf[0] = 42  // Should not track buf[0] as allocation
    defer free(buf)  // Single free - OK
}
```

## 🎉 Final Goal

**Production-ready C002 rule that:**
- ✅ Detects double-free patterns reliably
- ✅ Works on all real Odin code
- ✅ No crashes or memory leaks
- ✅ Zero false positives
- ✅ Maintainable implementation

**Status**: Resolution plan created - ready for implementation! 🚀