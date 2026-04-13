; odin2026_migration.scm — C009 (core:os/old import) + C010 (Small_Array usage)
; Predicates not evaluated; filtering done in Odin code.

; C009: import declarations — capture string content for path comparison
(import_declaration
  (string (string_content) @c009_path))

; C010-a: polymorphic_type — matches T(N, T) in type annotation position
;   e.g. arr: Small_Array(8, int)
;   Captures the whole node; Odin code extracts the leading type name from source text
;   and filters for "Small_Array".
;   NOTE: (identifier) child fails with Structure error because polymorphic_type
;   declares its children as supertype 'type', not concrete 'identifier'.
(polymorphic_type) @c010_poly

; C010-b: call_expression — matches Small_Array(N, T) in expression position
;   e.g. x := Small_Array(8, int){}
;   Odin code filters: function identifier == "Small_Array"
(call_expression
  function: (identifier) @c010_fn)
