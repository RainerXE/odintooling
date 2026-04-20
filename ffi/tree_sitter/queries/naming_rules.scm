; naming_rules.scm — captures for C003 (proc naming) and C007 (type naming)
;
; Each match contains ONE of the following captures depending on which
; declaration matched.  The Odin-side matcher inspects which key is present
; and applies the appropriate rule.
;
; C003: procedure names must start with lowercase (camelCase or snake_case).
;       Flag names starting with an uppercase letter (PascalCase = type convention).
;
; C007: struct / enum / union type names must start with uppercase (PascalCase).
;       Flag names starting with a lowercase letter.

; C003 — procedure declarations
(procedure_declaration
  (identifier) @proc_name)

; C003 — overloaded procedure declarations (proc groups)
(overloaded_procedure_declaration
  (identifier) @proc_name)

; C007 — struct type declarations
(struct_declaration
  (identifier) @struct_name)

; C007 — enum type declarations
(enum_declaration
  (identifier) @enum_name)

; C016 — local variable declarations inside proc bodies (:= assignments)
; Note: assignment_statement covers both := and = — Odin code filters to := only
(assignment_statement
  (identifier) @local_var)

; C017 — package-level mutable variable (:= at package scope)
; variable_declaration is ONLY emitted at package scope (inside proc bodies
; use assignment_statement instead) — no scope filtering needed in Odin code.
(variable_declaration
  (identifier) @pkg_var)
