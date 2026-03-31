package core

import "core:c"

// Tree-sitter types (opaque pointers)
TSParser :: distinct rawptr;
TSTree :: distinct rawptr;
TSNode :: distinct rawptr;
TSLanguage :: distinct rawptr;
TSQuery :: distinct rawptr;
TSQueryCursor :: distinct rawptr;

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

	// Language functions (would need Odin language implementation)
	// ts_language_symbol_count :: proc "c"(language: TSLanguage) -> c.uint ---;
	// ts_language_symbol_name :: proc "c"(language: TSLanguage, symbol: c.ushort) -> ^c.char ---;
}