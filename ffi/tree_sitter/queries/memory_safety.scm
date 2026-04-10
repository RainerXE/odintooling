; memory_safety.scm
; Captures for C001 (memory allocation without defer free)
; and C002 (double-free via defer).

(short_var_decl
  (identifier_list (identifier) @var_name)
  (expression_list
    (call_expression
      function: (identifier) @alloc_fn
      (#match? @alloc_fn "^(make|new)$")))) @alloc

(defer_statement
  (call_expression
    function: (identifier) @cleanup_fn
    (#match? @cleanup_fn "^(free|delete)$")
    arguments: (argument_list (identifier) @freed_var))) @defer_free