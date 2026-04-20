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

; Package-level constant declarations (NAME :: value)
; NOTE: (identifier) also matches identifiers in the value — Pass 1 filters to
; the name side by checking column < position of '::' in the source line.
(const_declaration
  (identifier) @const_name) @const_decl

; Package-level inferred variable declarations (name := value)
; variable_declaration is ONLY produced at package scope; inside procs the
; same syntax becomes assignment_statement.
(variable_declaration
  (identifier) @pkg_var) @pkg_var_decl

; Package-level explicit-type variable declarations (name: Type = value)
; NOTE: same dedup concern — Pass 1 checks column < position of ':'.
(var_declaration
  (identifier) @var_name) @var_decl
