package core

import "core:fmt"
import "core:os"
import "core:c"
import "core:strings"
import "base:runtime"



// Tree-sitter integration module
// This is the real implementation using tree-sitter C bindings

// Use the types directly from the bindings
// (types are defined in tree_sitter_bindings.odin)

// initTreeSitter initializes the tree-sitter system
initTreeSitter :: proc() -> (TSParser, TSLanguage, bool) {
    fmt.println("Initializing tree-sitter")
    
    // Create parser instance
    parser := ts_parser_new()
    if parser == nil {
        fmt.println("Failed to create parser")
        return nil, nil, false
    }
    
    // Load Odin language grammar (placeholder - need to implement)
    // For now, we'll return nil for language
    language: TSLanguage
    
    return parser, language, true
}

// deinitTreeSitter cleans up tree-sitter resources
deinitTreeSitter :: proc(parser: TSParser, language: TSLanguage) {
    fmt.println("Cleaning up tree-sitter")
    if parser != nil {
        ts_parser_delete(parser)
    }
    // Language cleanup would go here if needed
}

// parseSource parses source code and returns a syntax tree
parseSource :: proc(parser: TSParser, language: TSLanguage, source: string) -> (TSTree, bool) {
    fmt.println("Parsing source with tree-sitter")
    
    // Set parser language (placeholder - need to implement)
    // if language != nil {
    //     success := ts_parser_set_language(parser, language)
    //     if !success {
    //         fmt.println("Failed to set parser language")
    //         return nil, false
    //     }
    // }
    
    // Parse source code
    // Convert string to cstring, then get ^u8 pointer for the C function
    source_cstr := strings.unsafe_string_to_cstring(source)
    source_ptr := (^u8)(source_cstr)
    tree := ts_parser_parse_string(parser, nil, source_ptr, c.uint(len(source)))
    if tree == nil {
        fmt.println("Failed to parse source")
        return nil, false
    }
    
    return tree, true
}

// getRootNode gets the root node of a syntax tree
getRootNode :: proc(tree: TSTree) -> TSNode {
    if tree == nil {
        return nil
    }
    return ts_tree_root_node(tree)
}

// convertToASTNode converts a tree-sitter node to our ASTNode format
convertToASTNode :: proc(ts_node: TSNode, source: string) -> ASTNode {
    if ts_node == nil {
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
        node_type = strings.string_from_null_terminated_ptr(node_type_ptr, len(source))
    }
    
    // Get node position
    start_byte := ts_node_start_byte(ts_node)
    end_byte := ts_node_end_byte(ts_node)
    
    // Extract text from source
    text := source[int(start_byte):int(end_byte)]
    
    // Convert children (simplified - need to implement proper child traversal)
    children: [dynamic]ASTNode
    child_count := ts_node_child_count(ts_node)
    for i in 0..<int(child_count) {
        child_node := ts_node_child(ts_node, c.uint(i))
        if child_node != nil {
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
        start_line = 1, // Placeholder
        start_column = 1, // Placeholder
        end_line = 1, // Placeholder
        end_column = 1, // Placeholder
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
    
    root := getRootNode(tree)
    ast_root := convertToASTNode(root, source)
    
    return ast_root, true
}