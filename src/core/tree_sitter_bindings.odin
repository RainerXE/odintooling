package core

import "core:c"

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