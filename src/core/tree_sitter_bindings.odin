// tree_sitter_bindings.odin — raw FFI bindings to libtree-sitter and libtree-sitter-odin.
// Declares the C types (TSNode, TSTree, TSParser, TSPoint …) and foreign procedure
// imports used by tree_sitter.odin and query_engine.odin.
package core

import "core:c"

// =============================================================================
// Odin Grammar Reference — Node Types for SCM Queries
// =============================================================================
//
// Critical grammar facts learned from implementing C002, C003, C007, C012.
// Check these before writing a new .scm query to avoid silent zero-match bugs.
//
// VARIABLE DECLARATIONS
//   x := value        → assignment_statement  (inside proc bodies)
//   x := value        → variable_declaration  (at PACKAGE scope only)
//   x: Type           → var_declaration        (both scopes)
//   x: Type = value   → var_declaration        (both scopes)
//   X :: value        → const_declaration
//
//   ⚠️  Do NOT use variable_declaration to match := inside procedures.
//       It only fires at package level. Use assignment_statement instead.
//       assignment_statement covers both = (reassign) and := (declare).
//
// PROCEDURE / TYPE DECLARATIONS
//   foo :: proc() {}              → procedure_declaration
//   Foo :: proc() {} | bar :: proc() {} → overloaded_procedure_declaration
//   Foo :: struct { … }           → struct_declaration
//   Foo :: enum { … }             → enum_declaration
//
// CALL EXPRESSIONS
//   make(T, n)                    → call_expression  function:(identifier)
//   mem.free(p)                   → member_expression containing call_expression
//                                   NOT selector_expression (that is ->)
//   foo->bar(p)                   → selector_call_expression (-> syntax)
//
// DEFER
//   defer free(p)                 → defer_statement(call_expression)
//   defer mem.free(p)             → defer_statement(member_expression(call_expression))
//
// SLICE / INDEX
//   buf[a:b]                      → slice_expression  fields: start, end
//   buf[i]                        → index_expression
//
// EXPRESSION SUPERTYPES
//   expression is a supertype (union) of: identifier, call_expression,
//   slice_expression, member_expression, binary_expression, etc.
//   Supertypes are transparent in queries — match the subtype directly.
//
// ABI NOTE
//   TSNode must match C layout exactly:
//   { uint32_t context[4]; const void *id; const TSTree *tree; } = 32 bytes
//   ctx must be [4]u32 (16 bytes), NOT [4]rawptr (32 bytes).
//
// =============================================================================

// Tree-sitter types (opaque pointers)
TSParser :: distinct rawptr;
TSTree :: distinct rawptr;
TSLanguage :: distinct rawptr;
TSQuery :: distinct rawptr;
TSQueryCursor :: distinct rawptr;

// TSNode is a value type struct, not a pointer
// Layout must match C: { uint32_t context[4]; const void *id; const TSTree *tree; } = 32 bytes
TSNode :: struct {
    ctx: [4]u32,  // 16 bytes — matches C uint32_t context[4]
    id:  rawptr,  // 8 bytes
    tree: rawptr, // 8 bytes
}  // Total: 32 bytes

// Query API types (M3.1)
TSQueryError :: enum u32 {
    None      = 0,
    Syntax    = 1,
    NodeType  = 2,
    Field     = 3,
    Capture   = 4,
    Structure = 5,
    Language  = 6,
}

TSQueryCapture :: struct {
    node:  TSNode,
    index: u32,
}

TSQueryMatch :: struct {
    id:            u32,
    pattern_index: u16,
    capture_count: u16,
    captures:      ^TSQueryCapture,
}

// Tree-sitter structures
TSPoint :: struct {
    row: c.uint,
    column: c.uint,
}

// Tree-sitter bindings
// Based on the tree-sitter C API: https://tree-sitter.github.io/tree-sitter/using-parsers#the-tree-sitter-c-api

// Import the static library
foreign {
	// Parser functions
	ts_parser_new :: proc "c"() -> TSParser ---;
	ts_parser_delete :: proc "c"(parser: TSParser) ---;
	ts_parser_set_language :: proc "c"(parser: TSParser, language: TSLanguage) -> c.bool ---;

	// Parsing
	ts_parser_parse_string :: proc "c"(
		parser: TSParser,
		old_tree: TSTree,
		source_code: ^u8,
		length: c.uint,
	) -> TSTree ---;

	// Tree functions
	ts_tree_root_node :: proc "c"(tree: TSTree) -> TSNode ---;
	ts_tree_delete :: proc "c"(tree: TSTree) ---;

	// Node functions
	ts_node_type :: proc "c"(node: TSNode) -> cstring ---;
	ts_node_start_byte :: proc "c"(node: TSNode) -> c.uint ---;
	ts_node_end_byte :: proc "c"(node: TSNode) -> c.uint ---;
	ts_node_start_point :: proc "c"(node: TSNode) -> TSPoint ---;
	ts_node_end_point :: proc "c"(node: TSNode) -> TSPoint ---;
	ts_node_child_count :: proc "c"(node: TSNode) -> c.uint ---;
	ts_node_child :: proc "c"(node: TSNode, index: c.uint) -> TSNode ---;
	ts_node_parent :: proc "c"(node: TSNode) -> TSNode ---;
	ts_node_is_null :: proc "c"(node: TSNode) -> c.bool ---;

	// Language functions
	// Odin language from tree-sitter-odin library
	tree_sitter_odin :: proc "c"() -> TSLanguage ---;

	// Language version functions for debugging ABI compatibility
	ts_language_abi_version :: proc "c"(language: TSLanguage) -> c.uint ---;

	// Tree functions for debugging
	ts_tree_language :: proc "c"(tree: TSTree) -> TSLanguage ---;
	ts_tree_root_node_with_offset :: proc "c"(tree: TSTree, offset: c.uint, extent: TSPoint) -> TSNode ---;
	ts_tree_print_dot_graph :: proc "c"(tree: TSTree, file_descriptor: c.int) ---;

	// Language functions (would need Odin language implementation)
	// ts_language_symbol_count :: proc "c"(language: TSLanguage) -> c.uint ---;
	// ts_language_symbol_name :: proc "c"(language: TSLanguage, symbol: c.ushort) -> ^c.char ---;

	// --- Query API (M3.1) ---
	ts_query_new :: proc "c"(
		language:     rawptr,
		source:       cstring,
		source_len:   u32,
		error_offset: ^u32,
		error_type:   ^TSQueryError,
	) -> rawptr ---;
	ts_query_delete             :: proc "c"(query: rawptr) ---;
	ts_query_capture_count      :: proc "c"(query: rawptr) -> u32 ---;
	ts_query_capture_name_for_id :: proc "c"(
		query:   rawptr,
		id:      u32,
		length:  ^u32,
	) -> cstring ---;
	ts_query_cursor_new         :: proc "c"() -> rawptr ---;
	ts_query_cursor_delete      :: proc "c"(cursor: rawptr) ---;
	ts_query_cursor_exec        :: proc "c"(cursor: rawptr, query: rawptr, node: TSNode) ---;
	ts_query_cursor_next_match  :: proc "c"(cursor: rawptr, match: ^TSQueryMatch) -> bool ---;
	// Returns S-expression string of a subtree — for debug only. Caller must free via libc free().
	ts_node_string :: proc "c"(node: TSNode) -> cstring ---;
}