; references.scm - captures call sites for the DNA call graph
;
; Used by dna_exporter.odin Pass 2 to populate the edges table.
; Captures direct calls only; qualified pkg.Foo calls resolved in Odin code.

; Direct function call: foo(...)
(call_expression
  function: (identifier) @callee) @call_site
