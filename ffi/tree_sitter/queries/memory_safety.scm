; memory_safety.scm
; Captures for C002 (double-free via defer).

(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#eq? @cleanup_fn "free"))) @defer_free

(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#eq? @cleanup_fn "delete"))) @defer_free