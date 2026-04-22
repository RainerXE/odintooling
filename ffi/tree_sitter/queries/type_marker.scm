; type_marker.scm — C019: type marker suffix conventions
;
; Captures variable names from three declaration forms.
; Odin code (c019_scm_run) handles all filtering, type extraction, and suffix checks.
;
; NOTE: Predicates (#eq?, #match?) are NOT evaluated by run_query.
;       All logic lives in Odin code.
;
; NOTE: These patterns capture ALL identifiers inside each declaration, including
;       type-name identifiers on the RHS. Odin code filters to the variable name
;       by checking column position < position of ':' or ':=' in the source line.

; Package-level explicit type declarations: name: Type [= value]
(var_declaration
  (identifier) @c019_var) @c019_var_decl

; Function parameters: proc(name: Type)
(parameter
  (identifier) @c019_param) @c019_param_decl

; Local variable introduction inside proc bodies (:= assignments)
; Odin code filters to := only (re-assignments without := are skipped).
(assignment_statement
  (identifier) @c019_local) @c019_local_assign
