package core

import "core:c"

// Tree-sitter types (opaque pointers)
TSParser :: distinct rawptr;
TSTree :: distinct rawptr;
TSNode :: distinct rawptr;
TSLanguage :: distinct rawptr;
TSQuery :: distinct rawptr;
TSQueryCursor :: distinct rawptr;

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
	ts_node_child_count :: proc "c"(node: TSNode) -> c.uint ---;
	ts_node_child :: proc "c"(node: TSNode, index: c.uint) -> TSNode ---;

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
}