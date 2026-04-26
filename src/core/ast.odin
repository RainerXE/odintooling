// ast.odin — ASTNode type, tree conversion, and walker utilities.
// convertToASTNode wraps tree-sitter TSNode into the ASTNode struct used by C001,
// C101, C029, C033, and other rules that need the custom ASTNode-based walker.
package core

import "core:fmt"
import "core:os"
import "base:runtime"

// TreeSitterParser represents the tree-sitter parser
TreeSitterParser :: struct {
    parser: rawptr,  // Will hold the tree-sitter parser
    language: rawptr, // Will hold the Odin language definition
}

// initParser initializes the tree-sitter parser
initParser :: proc() -> TreeSitterParser {
    return TreeSitterParser{
        parser = nil,
        language = nil,
    }
}

// deinitParser cleans up the parser
deinitParser :: proc(parser: TreeSitterParser) {
    // Placeholder for actual cleanup
}

// TreeSitterASTParser represents a parser using tree-sitter
TreeSitterASTParser :: struct {
    adapter: TreeSitterASTAdapter,
}

// initTreeSitterParser initializes a tree-sitter-based parser
initTreeSitterParser :: proc() -> (TreeSitterASTParser, bool) {
    adapter, ok := initASTAdapter()
    if !ok {
        return TreeSitterASTParser{}, false
    }
    
    return TreeSitterASTParser{
        adapter = adapter,
    }, true
}

// deinitTreeSitterParser cleans up the parser
deinitTreeSitterParser :: proc(parser: TreeSitterASTParser) {
    deinitASTAdapter(parser.adapter)
}

// parseFile parses an Odin file and returns the AST root node
parseFile :: proc(parser: TreeSitterASTParser, file_path: string) -> (ASTNode, bool) {
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return ASTNode{}, false
    }
    defer delete(content)

    ast_root, ok := parseToAST(parser.adapter, string(content))
    if !ok {
        return ASTNode{}, false
    }
    return ast_root, true
}

// ASTNode represents a node in the AST
ASTNode :: struct {
    node_type: string,
    start_line: int,
    start_column: int,
    end_line: int,
    end_column: int,
    text: string,
    children: []ASTNode,
}

// walkAST walks the AST and applies visitor functions
walkAST :: proc(node: ^ASTNode, visitor: proc(node: ^ASTNode) -> bool) {
    if node == nil {
        return
    }
    
    // Apply visitor to current node
    if !visitor(node) {
        return  // Stop walking if visitor returns false
    }
    
    // Recursively visit children
    for &child in node.children {
        walkAST(&child, visitor)
    }
}

// ASTVisitor defines the visitor interface for AST nodes
ASTVisitor :: struct {
    enter_node: proc(node: ^ASTNode) -> bool,
    leave_node: proc(node: ^ASTNode),
}

// visitAST visits the AST using a visitor pattern
visitAST :: proc(node: ^ASTNode, visitor: ASTVisitor) {
    if node == nil {
        return
    }
    
    // Enter node
    if !visitor.enter_node(node) {
        return  // Stop visiting if enter returns false
    }
    
    // Visit children
    for &child in node.children {
        visitAST(&child, visitor)
    }
    
    // Leave node
    visitor.leave_node(node)
}
// is_ident_byte returns true if b is a valid Odin identifier character.
// Canonical version — avoids duplicating this helper across rule files.
is_ident_byte :: proc(b: u8) -> bool {
    return b == '_' || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')
}
