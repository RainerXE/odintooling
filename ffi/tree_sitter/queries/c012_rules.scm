; c012_rules.scm — C012: semantic ownership naming hints
; Rule tier: INFO (opt-in, never VIOLATION)
; Enable via: odin-lint --enable-c012 or odin-lint.toml [rules.C012] enabled=true
;
; IMPORTANT: In Odin's tree-sitter grammar, := inside procedure bodies is an
; assignment_statement (handles both = and :=). variable_declaration is ONLY
; for package-level declarations. So all patterns use assignment_statement.
;
; NOTE: Predicates (#match?, #not-match?) are NOT evaluated by our run_query.
; All name/value filtering is done in Odin code inside c012_scm_run.
;
; Captures use unique prefixes to avoid collision with naming_rules.scm.

; C012-S1: make/new allocation without _owned suffix
; Odin code checks: fn == "make" or "new", var does not end with "_owned"
(assignment_statement
  (identifier) @c012_alloc_var
  (call_expression
    function: (identifier) @c012_alloc_fn))

; C012-S2: slice expression without _view or _borrowed suffix
; Odin code checks: var does not contain "_view" or "_borrowed"
(assignment_statement
  (identifier) @c012_slice_var
  (slice_expression))

; C012-S3: package-qualified allocator call without alloc/allocator in name
; Matches mem.tracking_allocator(), mem.arena_allocator(), etc.
; Odin code checks: fn in known allocator set, var does not contain "alloc"
(assignment_statement
  (identifier) @c012_qalloc_var
  (member_expression
    (call_expression
      function: (identifier) @c012_qalloc_fn)))
