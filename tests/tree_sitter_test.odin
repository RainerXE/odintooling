package main

import "core:fmt"
import "core:os"
import "core:c"
import "core:strings"

// Minimal tree-sitter test
foreign {
    ts_parser_new :: proc "c"() -> rawptr ---;
    ts_parser_delete :: proc "c"(parser: rawptr) ---;
    ts_parser_set_language :: proc "c"(parser: rawptr, language: rawptr) -> c.bool ---;
    ts_parser_parse_string :: proc "c"(
        parser: rawptr,
        old_tree: rawptr,
        source_code: ^u8,
        length: c.uint,
    ) -> rawptr ---;
    ts_tree_root_node :: proc "c"(tree: rawptr) -> rawptr ---;
    tree_sitter_odin :: proc "c"() -> rawptr ---;
}

main :: proc() {
    fmt.println("Testing tree-sitter integration...")
    
    // Create parser
    parser := ts_parser_new()
    if parser == nil {
        fmt.println("❌ Failed to create parser")
        os.exit(1)
    }
    
    // Load Odin language
    language := tree_sitter_odin()
    if language == nil {
        fmt.println("❌ Failed to load Odin language")
        os.exit(1)
    }
    
    // Set language
    success := ts_parser_set_language(parser, language)
    if !success {
        fmt.println("❌ Failed to set parser language")
        os.exit(1)
    }
    
    // Test source code
    source := "proc main() { fmt.println(\"hello\"); }"
    source_cstr := strings.unsafe_string_to_cstring(source)
    source_ptr := (^u8)(source_cstr)
    
    fmt.println("Parsing source code...")
    
    // Parse
    tree := ts_parser_parse_string(parser, nil, source_ptr, c.uint(len(source)))
    if tree == nil {
        fmt.println("❌ Failed to parse source")
        os.exit(1)
    }
    
    fmt.println("Getting root node...")
    
    // Get root node
    root := ts_tree_root_node(tree)
    if root == nil {
        fmt.println("❌ Failed to get root node")
        os.exit(1)
    }
    
    fmt.println("✅ Tree-sitter integration working!")
    ts_parser_delete(parser)
    os.exit(0)
}