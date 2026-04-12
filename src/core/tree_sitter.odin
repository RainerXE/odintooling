package core

import "core:fmt"
import "core:os"
import "core:c"
import "core:strings"
import "base:runtime"

// Tree-sitter version constants for ABI compatibility checking
TREE_SITTER_LANGUAGE_VERSION :: 14
TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION :: 13



// Tree-sitter integration module
// This is the real implementation using tree-sitter C bindings

// Use the types directly from the bindings
// (types are defined in tree_sitter_bindings.odin)

// initTreeSitter initializes the tree-sitter system
initTreeSitter :: proc() -> (TSParser, TSLanguage, bool) {
    parser := ts_parser_new()
    if parser == nil {
        return nil, nil, false
    }

    language := tree_sitter_odin()
    if language == nil {
        ts_parser_delete(parser)
        return nil, nil, false
    }

    success := ts_parser_set_language(parser, language)
    if !success {
        ts_parser_delete(parser)
        return nil, nil, false
    }

    return parser, language, true
}

// deinitTreeSitter cleans up tree-sitter resources
deinitTreeSitter :: proc(parser: TSParser, language: TSLanguage) {
    if parser != nil {
        ts_parser_delete(parser)
    }
    // Language cleanup would go here if needed
}

// parseSource parses source code and returns a syntax tree
parseSource :: proc(parser: TSParser, language: TSLanguage, source: string) -> (TSTree, bool) {
    source_cstr := strings.unsafe_string_to_cstring(source)
    source_ptr := (^u8)(source_cstr)
    tree := ts_parser_parse_string(parser, nil, source_ptr, c.uint(len(source)))
    if tree == nil {
        return nil, false
    }
    return tree, true
}

// getRootNode gets the root node of a syntax tree
getRootNode :: proc(tree: TSTree) -> TSNode {
    if tree == nil {
        return TSNode{}
    }
    root := ts_tree_root_node(tree)
    if ts_node_is_null(root) {
        return TSNode{}
    }
    return root
}

// convertToASTNode converts a tree-sitter node to our ASTNode format
convertToASTNode :: proc(ts_node: TSNode, source: string) -> ASTNode {
    if ts_node_is_null(ts_node) {
        return ASTNode{
            node_type = "invalid",
            start_line = 1,
            start_column = 1,
            end_line = 1,
            end_column = 1,
            text = "",
            children = []ASTNode{},
        }
    }
    
    // Get node type
    node_type_ptr := ts_node_type(ts_node)
    node_type := "unknown" // Default value
    if node_type_ptr != nil {
        // Convert ^u8 to string - tree-sitter returns null-terminated C strings
        node_type = strings.string_from_null_terminated_ptr(node_type_ptr, 1024)
    }
    
    // Get node position
    start_byte := ts_node_start_byte(ts_node)
    end_byte := ts_node_end_byte(ts_node)
    
    // Get line and column positions
    start_point := ts_node_start_point(ts_node)
    end_point := ts_node_end_point(ts_node)
    
    // Extract text from source
    text := source[int(start_byte):int(end_byte)]
    
    // Convert children (simplified - need to implement proper child traversal)
    children: [dynamic]ASTNode
    child_count := ts_node_child_count(ts_node)
    for i in 0..<int(child_count) {
        child_node := ts_node_child(ts_node, c.uint(i))
        if !ts_node_is_null(child_node) {
            child_ast := convertToASTNode(child_node, source)
            runtime.append_elem(&children, child_ast)
        }
    }
    
    // Note: This is a simplified conversion
    // In a real implementation, you'd need to:
    // 1. Properly calculate line/column positions
    // 2. Handle different node types appropriately
    // 3. Implement proper memory management
    
    return ASTNode{
        node_type = node_type,
        start_line = int(start_point.row) + 1, // tree-sitter uses 0-based line numbers
        start_column = int(start_point.column) + 1, // tree-sitter uses 0-based column numbers
        end_line = int(end_point.row) + 1,
        end_column = int(end_point.column) + 1,
        text = text,
        children = children[:],
    }
}

// TreeSitterASTAdapter adapts tree-sitter to our AST system
TreeSitterASTAdapter :: struct {
    parser: TSParser,
    language: TSLanguage,
}

// initASTAdapter creates a new AST adapter
initASTAdapter :: proc() -> (TreeSitterASTAdapter, bool) {
    parser, language, ok := initTreeSitter()
    if !ok {
        return TreeSitterASTAdapter{}, false
    }
    
    return TreeSitterASTAdapter{
        parser = parser,
        language = language,
    }, true
}

// deinitASTAdapter cleans up the adapter
deinitASTAdapter :: proc(adapter: TreeSitterASTAdapter) {
    deinitTreeSitter(adapter.parser, adapter.language)
}

// parseToAST parses source code to our AST format
parseToAST :: proc(adapter: TreeSitterASTAdapter, source: string) -> (ASTNode, bool) {
    tree, ok := parseSource(adapter.parser, adapter.language, source)
    if !ok {
        return ASTNode{}, false
    }
    
    tree_language := ts_tree_language(tree)
    if tree_language == nil {
        return ASTNode{}, false
    }

    root := getRootNode(tree)
    if ts_node_is_null(root) {
        // Fallback: try root node with zero offset
        zero_point := TSPoint{row = 0, column = 0}
        root = ts_tree_root_node_with_offset(tree, 0, zero_point)
        if ts_node_is_null(root) {
            return ASTNode{}, false
        }
    }
    
    ast_root := convertToASTNode(root, source)

    return ast_root, true
}