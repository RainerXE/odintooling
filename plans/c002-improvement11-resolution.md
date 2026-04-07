# C002 Improvement Phase 11 - Resolution Plan

## 🎯 Objective
Address critical bugs and design issues in C002 implementation based on comprehensive code review.

## 🚨 Critical Issues Summary

### **Blockers (Rule Currently Non-Functional)**
1. **node.text reliance** - Extraction functions fail silently on real code
2. **Wrong node type name** - `short_var_declaration` vs correct `short_var_decl`
3. **Scope tracking bugs** - Uses substring match instead of exact match
4. **Cross-function context** - Shared context causes false negatives

### **Design Issues**
5. **Rule purpose mismatch** - Implements double-free detection, not wrong-pointer detection
6. **Memory management** - Leaks dynamic slices
7. **Missing file caching** - Needed for text extraction

## 🔧 Resolution Plan

### Phase 1: Fix Critical Bugs (Make Rule Functional)

#### **1. Fix node.text Reliance - Use AST Navigation**
**Problem**: `extract_lhs_var_name` and `extract_var_name_from_free` use `node.text` which is empty/unreliable.

**Solution**: Replace with AST navigation like C001:
```odin
// Replace extract_lhs_var_name with AST-based approach
extract_lhs_var_name :: proc(node: ^ASTNode) -> string {
    // Navigate to first identifier child (like C001's extract_lhs_name)
    for &child in node.children {
        if child.node_type == "identifier" {
            return child.text
        }
    }
    return ""
}

// Replace extract_var_name_from_free with AST-based approach
extract_var_name_from_free :: proc(node: ^ASTNode) -> string {
    // Navigate call_expression → argument_list → identifier
    // Reuse C001's extract_freed_var_name logic
}
```

**Files to modify**:
- `src/core/c002-COR-Pointer.odin` - Replace text parsing with AST navigation
- Share functions with C001 to avoid duplication

#### **2. Fix Node Type Name**
**Problem**: Uses `"short_var_declaration"` but tree-sitter uses `"short_var_decl"`.

**Fix**:
```odin
// Line 66: Change from
if node.node_type == "assignment_statement" || node.node_type == "short_var_declaration" {
// To
if node.node_type == "assignment_statement" || node.node_type == "short_var_decl" {
```

**Impact**: This single fix will make := declarations work.

#### **3. Fix Scope Tracking**
**Problem**: `strings.contains(node.node_type, "block")` matches any node containing "block".

**Fix**:
```odin
// Change from substring match
is_block := strings.contains(node.node_type, "block")
// To exact match
is_block := node.node_type == "block"
```

**Files**: `src/core/c002-COR-Pointer.odin` line ~150

#### **4. Fix Context Sharing**
**Problem**: Context shared across entire file causes cross-function false negatives.

**Solution**: Reset context at procedure boundaries:
```odin
// In c002Matcher, add proc boundary detection
if node.node_type == "proc_declaration" {
    // Save current context
    // Create new context for this procedure
    // Process procedure body
    // Restore parent context
}
```

**Alternative**: Pass scope as parameter instead of mutable context.

### Phase 2: Design Clarification

#### **5. Clarify Rule Purpose**
**Current**: Detects double-free (free_count > 1)
**Stated Purpose**: "Defer free on wrong pointer"

**Options**:
1. **Rename to "Double-Free Detection"** - Match current implementation
2. **Implement wrong-pointer detection** - Match stated purpose

**Recommendation**: Option 1 (rename) is simpler and more valuable. Double-free detection is a real, common bug pattern.

**Action**:
- Update rule name and documentation
- Update diagnostic messages
- Keep current detection logic

#### **6. Remove Non-Odin Functions**
**Problem**: Checks for `alloc` and `malloc` which aren't Odin builtins.

**Fix**:
```odin
// Remove these lines
else if callee_text == "alloc" || callee_text == "malloc" {
```

**Keep**: `make`, `new` (Odin builtins)

### Phase 3: Code Quality Improvements

#### **7. Add Compound Assignment Operators**
**Problem**: Relational guard missing `+=`, `-=`, `*=`, etc.

**Fix**:
```odin
has_relational_op := strings.contains(text, ">=") || 
                   strings.contains(text, "<=") || 
                   strings.contains(text, "!=") ||
                   strings.contains(text, "==") ||
                   strings.contains(text, "+=") ||
                   strings.contains(text, "-=") ||
                   strings.contains(text, "*=") ||
                   strings.contains(text, "/=") ||
                   strings.contains(text, "%=") ||
                   strings.contains(text, "&=") ||
                   strings.contains(text, "|=") ||
                   strings.contains(text, "^=") ||
                   strings.contains(text, "<<=") ||
                   strings.contains(text, ">>=")
```

**Better**: Replace text parsing with AST navigation entirely.

#### **8. Fix Memory Management**
**Problem**: Dynamic slices in `allocations_map` are never freed.

**Fix**:
```odin
// After analysis completes
defer {
    for key, value in ctx.allocations_map {
        delete(value)  // Free the dynamic slice
    }
    delete(ctx.allocations_map)  // Free the map
}
```

#### **9. Add File Caching**
**Problem**: No file caching for text extraction (needed when fixing node.text).

**Solution**: Reuse C001's file caching pattern:
```odin
// Add to C002AnalysisContext
file_lines: []string,
file_path: string,

// Initialize in create_c002_context
if file_path != ctx.file_path {
    ctx.file_lines = strings.split(read_file(file_path), "\n")
    ctx.file_path = file_path
}
```

#### **10. Fix create_c002_context**
**Problem**: Uses nil maps, never called.

**Fix**:
```odin
create_c002_context :: proc(file_path: string) -> C002AnalysisContext {
    return C002AnalysisContext{
        allocations_map = make(map[string][dynamic]C002AllocationInfo),
        current_scope = 0,
        scope_stack = make([dynamic]string),
        file_lines = strings.split(read_file(file_path), "\n"),
        file_path = file_path,
    }
}
```

## 📅 Timeline & Priority

### **Critical Fixes (Do Immediately - Rule Broken)**
1. Fix node.text reliance (AST navigation) - **HIGH**
2. Fix node type name - **HIGH**
3. Fix scope tracking - **HIGH**
4. Fix context sharing - **HIGH**

**Estimated**: 4-8 hours

### **Design Clarification (Do Next - Rule Purpose)**
5. Clarify rule purpose - **HIGH**
6. Remove non-Odin functions - **MEDIUM**

**Estimated**: 2-4 hours

### **Code Quality (Do After - Polish)**
7. Add compound operators - **MEDIUM**
8. Fix memory management - **MEDIUM**
9. Add file caching - **MEDIUM**
10. Fix create_c002_context - **LOW**

**Estimated**: 2-4 hours

## ✅ Success Criteria

### **Phase 1 Complete**
- ✅ C002 detects allocations in real code
- ✅ := declarations work correctly
- ✅ Scope tracking is accurate
- ✅ No cross-function false negatives

### **Phase 2 Complete**
- ✅ Rule purpose is clear and documented
- ✅ Only detects real Odin allocation patterns
- ✅ Consistent with stated purpose

### **Phase 3 Complete**
- ✅ No memory leaks
- ✅ Robust edge case handling
- ✅ Production-ready code quality

## 🎯 Expected Outcome

After completing this plan:
- **C002 will be functional** on real code (currently detects nothing)
- **Accurate detection** of double-free patterns
- **Clear purpose** and documentation
- **Production-ready** code quality
- **Maintainable** implementation

## 🔧 Implementation Strategy

### **Reuse C001 Patterns**
- Copy `extract_lhs_name` from C001
- Copy `extract_freed_var_name` from C001
- Copy file caching pattern from C001
- Copy scope management pattern from C001

### **Incremental Testing**
1. Fix node type name first → test := declarations
2. Fix AST navigation → test real code detection
3. Fix scope tracking → test nested scopes
4. Fix context sharing → test multiple procedures

### **Validation Plan**
- Test on Odin core libraries
- Test on RuiShin production code
- Test on OLS codebase
- Verify no false positives
- Verify correct detection of double-frees

## 📝 Documentation Updates Needed

1. **Update rule documentation** - Clarify what C002 actually detects
2. **Update examples** - Show double-free patterns
3. **Add limitations** - Document what C002 does NOT detect
4. **Update test expectations** - Reflect actual rule behavior

## 🎉 Final Goal

**Production-ready C002 rule that:**
- ✅ Detects double-free patterns reliably
- ✅ Works on real Odin code
- ✅ Has clear, documented purpose
- ✅ Zero false positives on clean code
- ✅ Maintainable implementation

**Status**: Resolution plan created - ready for implementation! 🚀