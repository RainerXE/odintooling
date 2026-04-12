; C002: Detect defer free(var) calls to find double-free patterns.
; Captures:
;   @cleanup_fn  — the function being called
;   @freed_var   — the identifier passed as the single argument

; Case 1: defer free(var)  — plain call e.g. defer free(data)
(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    argument: (identifier) @freed_var))

; Case 2: defer pkg.free(var)  — qualified call e.g. defer mem.free(data)
(defer_statement
  (member_expression
    (call_expression
      function: (identifier) @cleanup_fn
      argument: (identifier) @freed_var)))
