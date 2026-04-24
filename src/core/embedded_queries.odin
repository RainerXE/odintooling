package core

// Embedded SCM query sources — compiled into the binary at build time.
// Use these with load_query_src() so the binary has no runtime file dependencies.
// To add a new rule: add a #load constant here, call load_query_src() in main.odin.

MEMORY_SAFETY_SCM :: #load("../../ffi/tree_sitter/queries/memory_safety.scm",    string)
NAMING_RULES_SCM  :: #load("../../ffi/tree_sitter/queries/naming_rules.scm",     string)
C012_RULES_SCM    :: #load("../../ffi/tree_sitter/queries/c012_rules.scm",        string)
ODIN2026_SCM      :: #load("../../ffi/tree_sitter/queries/odin2026_migration.scm", string)
FFI_SAFETY_SCM    :: #load("../../ffi/tree_sitter/queries/ffi_safety.scm",        string)
DECLARATIONS_SCM  :: #load("../../ffi/tree_sitter/queries/declarations.scm",      string)
REFERENCES_SCM    :: #load("../../ffi/tree_sitter/queries/references.scm",        string)
TYPE_MARKER_SCM       :: #load("../../ffi/tree_sitter/queries/type_marker.scm",       string)
UNCHECKED_RESULT_SCM  :: #load("../../ffi/tree_sitter/queries/unchecked_result.scm",  string)
