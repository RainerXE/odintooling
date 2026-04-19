package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:c"
import "base:runtime"
import "core:mem"

// Quick test of query engine
main :: proc() {
    // Initialize tree-sitter
    parser, language, ok := initTreeSitter()
    if !ok {
        fmt.println("Failed to init tree-sitter")
        return
    }
    defer deinitTreeSitterParser(parser)
    
    // Test loading the simple query
    query, query_ok := load_query(language, "ffi/tree_sitter/queries/test_simple.scm")
    if query_ok {
        fmt.println("✅ Query loaded successfully")
        unload_query(&query)
    } else {
        fmt.println("❌ Query failed to load")
    }
}
