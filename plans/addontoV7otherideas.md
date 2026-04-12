Lessons Learned from the FFI Memory Bug

1. The Problem Space
The C/Odin FFI boundary has unique challenges:
•  
Memory ownership ambiguity: Who owns the memory? C or Odin?
•  Lifetime management: When is memory valid vs. freed?
•  Type safety: C pointers vs. Odin's type system
•  Error handling: C errors vs. Odin's error system
2. Specific Patterns That Caused Issues
A. Dangling Pointers from C Strings
// ❌ BUGGY: String views C memory that gets freed
raw_ptr := ts_query_capture_name_for_id(handle, i, &length)
name := strings.string_from_null_terminated_ptr(raw_ptr)  // Views C memory

// Later...
ts_query_delete(handle)  // Frees C memory
delete(name)  // ❌ USE-AFTER-FREE: name views freed memory

B. Resource Leaks

// ❌ BUGGY: Forgot to free C resource
handle := ts_query_new(language, source_ptr, length, &error_offset, &error_type)
// ... use handle ...
// ❌ LEAK: Never called ts_query_delete(handle)
C. Improper Error Handling

// ❌ BUGGY: Ignoring C error codes
error_offset: u32
error_type: TSQueryError
handle := ts_query_new(language, source_ptr, length, &error_offset, &error_type)
// ❌ IGNORED: Never checked error_type or error_offset
Proposed C00X Rule: FFI Memory Safety
Rule C00X: FFI Memory Ownership Violation
Tier: correctness Category: CORRECTNESS
Detection Patterns:

 1.  C String Copy Requirement
// ❌ VIOLATION: Direct use of C string pointer
raw_ptr := some_c_function_returning_string()
str := strings.string_from_null_terminated_ptr(raw_ptr)  // Should be cloned

// ✅ CORRECT: Explicit copy
raw_ptr := some_c_function_returning_string()
cstr := strings.string_from_null_terminated_ptr(raw_ptr)
str := strings.clone(cstr)  // Owns the memory

 2.  Resource Leak Detection
// ❌ VIOLATION: Unpaired allocation/free
handle := ts_query_new(...)  // Allocated
// ... no corresponding ts_query_delete ...

// ✅ CORRECT: Proper pairing
handle := ts_query_new(...)
defer ts_query_delete(handle)  // Explicit cleanup


 3.  Error Code Checking

// ❌ VIOLATION: Ignored error code
error_code := some_c_function_with_error_return()
// ... no error checking ...

// ✅ CORRECT: Explicit error handling
error_code := some_c_function_with_error_return()
if error_code != 0 {
    // Handle error
}
Implementation Approach
Option 1: Static Analysis Patterns
•  
Look for strings.string_from_null_terminated_ptr without subsequent clone
•  Track C resource allocations and verify they're freed
•  Check for ignored error return values from C functions
Option 2: Runtime Analysis (Shadow Mode)

•  Instrument FFI calls to track memory ownership
•  Verify that C resources are properly managed
•  Check that strings don't reference freed C memory
Option 3: Documentation + Linting

•  Create FFI best practices guide
•  Add lint rules for common FFI pitfalls
•  Provide safe wrappers for common C patterns

Example Implementation

Here's how the rule might look in code:

// In src/core/c00x-FFI-Memory.odin
C00XRule :: proc() -> Rule {
    return Rule{
        id       = "C00X",
        tier     = "correctness",
        category = .CORRECTNESS,
        matcher  = c00xMatcher,
        message  = c00x_message,
        fix_hint = c00x_fix_hint,
    }
}

c00xMatcher :: proc(file_path: string, node: ^ASTNode) -> []Diagnostic {
    diagnostics := make([dynamic]Diagnostic)

    // Pattern 1: C string without clone
    if is_c_string_without_clone(node) {
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = node.start_line,
            column    = node.start_column,
            rule_id   = "C00X",
            tier      = "correctness",
            message   = "C string pointer used without cloning - may become dangling",
            fix_hint  = "Use strings.clone() to copy C strings to stable memory",
            diag_type = .VIOLATION,
        })
    }

    // Pattern 2: Unpaired C resource allocation
    if is_unpaired_c_allocation(node) {
        append(&diagnostics, Diagnostic{
            file      = file_path,
            line      = node.start_line,
            column    = node.start_column,
            rule_id   = "C00X",
            tier      = "correctness",
            message   = "C resource allocated but never freed",
            fix_hint  = "Add defer ts_*_delete() or explicit cleanup",
            diag_type = .VIOLATION,
        })
    }

    return diagnostics
}

Benefits of This Approach


 1.  Prevents FFI bugs proactively: Catches issues before they cause crashes
 2.  Documents best practices: Makes FFI memory management explicit
 3.  Educates developers: Shows correct patterns for C/Odin interop
 4.  Complements C002: Extends memory safety to the FFI boundary