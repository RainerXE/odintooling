; declarations.scm — captures symbol declarations for the DNA call graph
;
; Used by dna_exporter.odin Pass 1 to populate the nodes table.
; Each match yields one of: @proc_name, @struct_name, @enum_name, @import_path.
;
; Note: overloaded_procedure_declaration wraps a proc group (multiple bodies
; under one name). Capture the group name as a proc node too.

; Procedure declarations
(procedure_declaration
  (identifier) @proc_name) @proc_decl

; Overloaded proc groups (proc { ... })
(overloaded_procedure_declaration
  (identifier) @proc_name) @proc_decl

; Struct type declarations
(struct_declaration
  (identifier) @struct_name) @type_decl

; Enum type declarations
(enum_declaration
  (identifier) @enum_name) @type_decl

; Import declarations — path only (alias captured separately if present)
(import_declaration
  (string (string_content) @import_path)) @import_decl
