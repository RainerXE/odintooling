package core

import "core:fmt"
import "core:os"
import "core:strings"
import "core:runtime"

// C001 Enhanced - Memory allocation safety with multiple cleanup patterns
//
// This rule checks for allocations without proper cleanup, supporting:
// 1. Standard: defer free(ptr)
// 2. Context: defer context.free(ptr)
// 3. Memory package: defer mem.free(ptr)
// 4. Custom functions: defer custom_free(ptr)
// 5. Tracking allocators: (no explicit free needed)

// Configuration for different cleanup patterns
AllocationCleanupPattern :: enum {
    STANDARD,    // defer free(ptr)
    CONTEXT,     // defer context.free(ptr)
    MEMORY,      // defer mem.free(ptr)
    CUSTOM,      // defer custom_function(ptr)
    TRACKING,    // Tracking allocator (no explicit free)
}

// Rule configuration
C001Config :: struct {
    // Which cleanup patterns to require
    required_patterns: [dynamic]AllocationCleanupPattern,
    
    // Allow allocations without explicit free if using tracking allocator
    allow_tracking_allocators: bool = true,
    
    // Custom cleanup function names to recognize
    custom_cleanup_functions: [dynamic]string,
}

// Enhanced C001 rule with configuration support
C001EnhancedRule :: proc() -> Rule {
    return Rule{
        id = "C001",
        tier = "correctness",
        matcher = c001_enhanced_matcher,
        message = c001_enhanced_message,
        fix_hint = c001_enhanced_fix_hint,
    }
}

// Configuration for different codebases
ols_config :: C001Config{
    required_patterns = [AllocationCleanupPattern.STANDARD, AllocationCleanupPattern.MEMORY],
    allow_tracking_allocators = true,
    custom_cleanup_functions = ["mem.free", "context.free"],
}

standard_config :: C001Config{
    required_patterns = [AllocationCleanupPattern.STANDARD],
    allow_tracking_allocators = false,
    custom_cleanup_functions = ["free"],
}

// Enhanced matcher that checks for multiple cleanup patterns
c001_enhanced_matcher :: proc(file_path: string, node: ^ASTNode, config: C001Config) -> Diagnostic {
    // Check if this is an allocation
    if !is_allocation_node(node) {
        return Diagnostic{}
    }
    
    // Read the entire file to check for cleanup patterns
    content, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return Diagnostic{}
    }
    defer delete(content)
    content_str := string(content)
    
    // Check if allocation uses tracking allocator
    if config.allow_tracking_allocators && 
       (strings.contains(node.text, "context.allocator") || 
        strings.contains(node.text, "tracking_allocator")) {
        return Diagnostic{}  // No violation - uses tracking system
    }
    
    // Check for any of the required cleanup patterns
    cleanup_found := false
    for pattern in config.required_patterns {
        switch pattern {
            case AllocationCleanupPattern.STANDARD:
                if strings.contains(content_str, "defer free") {
                    cleanup_found = true
                }
            case AllocationCleanupPattern.CONTEXT:
                if strings.contains(content_str, "defer context.free") {
                    cleanup_found = true
                }
            case AllocationCleanupPattern.MEMORY:
                if strings.contains(content_str, "defer mem.free") {
                    cleanup_found = true
                }
            case AllocationCleanupPattern.CUSTOM:
                for func in config.custom_cleanup_functions {
                    if strings.contains(content_str, "defer " + func) {
                        cleanup_found = true
                        break
                    }
                }
        }
    }
    
    if !cleanup_found {
        return Diagnostic{
            file = file_path,
            line = node.start_line,
            column = node.start_column,
            rule_id = "C001",
            tier = "correctness",
            message = "Allocation without matching cleanup",
            fix = generate_fix_hint(node, config),
            has_fix = true,
        }
    }
    
    return Diagnostic{}
}

// Generate appropriate fix hint based on configuration
generate_fix_hint :: proc(node: ^ASTNode, config: C001Config) -> string {
    if len(config.required_patterns) == 0 {
        return "Add appropriate cleanup for allocation"
    }
    
    // Suggest the most common pattern
    if config.required_patterns[0] == AllocationCleanupPattern.STANDARD {
        return "Add defer free() for allocated resource"
    } else if config.required_patterns[0] == AllocationCleanupPattern.CONTEXT {
        return "Add defer context.free() for allocated resource"
    } else if config.required_patterns[0] == AllocationCleanupPattern.MEMORY {
        return "Add defer mem.free() for allocated resource"
    }
    
    return "Add appropriate cleanup for allocation"
}

// Check if node is an allocation
is_allocation_node :: proc(node: ^ASTNode) -> bool {
    return strings.contains(node.text, "make") || 
           strings.contains(node.text, "new") ||
           strings.contains(node.text, "malloc") ||
           strings.contains(node.text, "calloc") ||
           strings.contains(node.text, "realloc")
}

// Export the enhanced rule
C001EnhancedRule :: proc() -> Rule {
    return Rule{
        id = "C001",
        tier = "correctness",
        matcher = c001_enhanced_matcher,
        message = c001_enhanced_message,
        fix_hint = c001_enhanced_fix_hint,
    }
}
