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
    fmt.println("=== DEBUG: Initializing tree-sitter ===")
    
    // Create parser instance
    fmt.println("DEBUG: Creating parser...")
    parser := ts_parser_new()
    if parser == nil {
        fmt.println("❌ DEBUG: ts_parser_new() returned nil")
        return nil, nil, false
    }
    fmt.println("✅ DEBUG: Parser created successfully")
    
    // Load Odin language grammar from tree-sitter-odin library
    fmt.println("DEBUG: Loading Odin language grammar...")
    language := tree_sitter_odin()
    if language == nil {
        fmt.println("❌ DEBUG: tree_sitter_odin() returned nil - grammar loading failed")
        ts_parser_delete(parser)
        return nil, nil, false
    }
    fmt.println("✅ DEBUG: Odin language loaded successfully")

    // Set the language in the parser
    fmt.println("DEBUG: Setting parser language...")
    success := ts_parser_set_language(parser, language)
    if !success {
        fmt.println("❌ DEBUG: ts_parser_set_language() returned false")
        ts_parser_delete(parser)
        return nil, nil, false
    }
    fmt.println("✅ DEBUG: Parser language set successfully")

    fmt.println("=== DEBUG: Tree-sitter initialization complete ===")
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
    fmt.println("=== DEBUG: Parsing source code ===")
    fmt.println("DEBUG: Source length:", len(source))
    fmt.println("DEBUG: Source content:", source)
    
    // Parse source code
    // Convert string to cstring, then get ^u8 pointer for the C function
    fmt.println("DEBUG: Converting string to C string...")
    source_cstr := strings.unsafe_string_to_cstring(source)
    source_ptr := (^u8)(source_cstr)
    fmt.println("DEBUG: Calling ts_parser_parse_string...")
    
    tree := ts_parser_parse_string(parser, nil, source_ptr, c.uint(len(source)))
    if tree == nil {
        fmt.println("❌ DEBUG: ts_parser_parse_string() returned nil")
        return nil, false
    }
    fmt.println("✅ DEBUG: Parsing successful, tree created")
    
    // Additional safety check - verify tree is not null
    if tree == nil {
        fmt.println("❌ DEBUG: Tree became nil after parsing (should not happen)")
        return nil, false
    }
    
    return tree, true
}

// getRootNode gets the root node of a syntax tree
getRootNode :: proc(tree: TSTree) -> TSNode {
    fmt.println("=== DEBUG: Getting root node ===")
    if tree == nil {
        fmt.println("❌ DEBUG: tree is nil")
        return nil
    }
    fmt.println("DEBUG: Tree is valid, calling ts_tree_root_node...")
    
    // This is where the crash occurs - let's see if we can catch it
    root := ts_tree_root_node(tree)
    if root == nil {
        fmt.println("❌ DEBUG: ts_tree_root_node() returned nil")
        return nil
    }
    fmt.println("✅ DEBUG: Root node obtained successfully")
    
    return root
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
    if root == nil {
        fmt.println("Failed to get root node from parsed tree")
        return ASTNode{}, false
    }
    
    ast_root := convertToASTNode(root, source)

    return ast_root, true
}