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
