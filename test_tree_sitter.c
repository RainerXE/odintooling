#include <stdio.h>
#include <string.h>
#include "tree_sitter/api.h"

// Include the Odin grammar
extern const TSLanguage *tree_sitter_odin(void);

int main() {
    printf("Testing tree-sitter with Odin grammar...\n");
    
    // Create parser
    TSParser *parser = ts_parser_new();
    if (!parser) {
        printf("❌ Failed to create parser\n");
        return 1;
    }
    printf("✅ Parser created\n");
    
    // Load language
    const TSLanguage *language = tree_sitter_odin();
    if (!language) {
        printf("❌ Failed to load language\n");
        return 1;
    }
    printf("✅ Language loaded\n");
    
    // Set language
    if (!ts_parser_set_language(parser, language)) {
        printf("❌ Failed to set language\n");
        return 1;
    }
    printf("✅ Language set\n");
    
    // Parse
    const char *source = "proc main() { x := 1 }";
    TSTree *tree = ts_parser_parse_string(
        parser, 
        NULL, 
        source, 
        strlen(source)
    );
    
    if (!tree) {
        printf("❌ Parsing failed\n");
        return 1;
    }
    printf("✅ Parsing successful\n");
    
    // Try to get root node
    TSNode root = ts_tree_root_node(tree);
    if (ts_node_is_null(root)) {
        printf("❌ Root node is null\n");
        return 1;
    }
    printf("✅ Root node accessed successfully\n");
    
    // Clean up
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    
    printf("✅ All tests passed!\n");
    return 0;
}