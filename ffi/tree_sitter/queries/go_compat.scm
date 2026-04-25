; go_compat.scm — C025: append without address-of
;
; Captures call_expression nodes for filtering in Odin code.
; Odin code checks:
;   C025: function is "append" AND first argument is not a &expr
;
; NOTE: C021 (Go fmt calls), C022 (Go range loop), C023 (C-style deref)
; use text-line scanning rather than SCM because the patterns involve
; invalid Odin syntax that tree-sitter may not parse correctly.
(call_expression) @go_compat_call
