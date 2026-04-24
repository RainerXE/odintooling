; unchecked_result.scm — C201: call whose error return is discarded
;
; Captures all call_expression nodes; Odin code filters by:
;   - parent node type == "block" (bare statement, not inside assignment)
;   - extracted proc name is in the error-returning set via TypeResolveContext
;
; Capture:
;   @c201_call  — the full call_expression node (location + parent check + fn name extraction)

(call_expression) @c201_call
