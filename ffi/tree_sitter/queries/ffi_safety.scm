; ffi_safety.scm — C011: FFI memory safety
; C011-P2: ts_*_new without matching defer ts_*_delete (block-scoped check)
; Predicates not evaluated; filtering done in Odin code.

; Capture ts_*_new allocations (assignment_statement, not variable_declaration)
(assignment_statement
  (identifier) @c011_handle
  (call_expression
    function: (identifier) @c011_new_fn))

; Capture defer ts_*_delete cleanups
(defer_statement
  (call_expression
    function: (identifier) @c011_del_fn
    argument: (identifier) @c011_del_arg))

; Capture return statements — returned handles transfer ownership (escape hatch)
(return_statement
  (identifier) @c011_return_var)
