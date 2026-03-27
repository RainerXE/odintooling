package core

import "core:fmt"
import "core:os"
import "core:strings"

// C001 rule implementation
// C001: Allocation without matching defer free in same scope
// Inspired by: Rust clippy::mem_forget

// C001Rule creates the C001 rule
C001Rule :: proc() -> Rule {
    return Rule{
        id = "C001",
        tier = "correctness",
        matcher = c001Matcher,
        message = c001Message,
        fix_hint = c001FixHint,
    }
}

// c001Matcher checks for allocations without defer free
c001Matcher :: proc(file_path: string, node: ^ASTNode) -> Diagnostic {
    // Placeholder - actual implementation will:
    // 1. Check if node is an allocation (make, new, etc.)
    // 2. Verify no matching defer free in same scope
    // 3. Return diagnostic if violation found
    
    fmt.println("C001 matcher called (placeholder)")
    
    // For now, return empty diagnostic (no violation)
    // When tree-sitter is integrated, this will:
    // 1. Convert rawptr to ASTNode
    // 2. Use visitor pattern to find allocations
    // 3. Check for matching defer free statements
    // 4. Return diagnostics for violations
    
    return Diagnostic{}
}

// c001Message returns the rule message
c001Message :: proc() -> string {
    return "Allocation without matching defer free in same scope"
}

// c001FixHint returns the fix hint
c001FixHint :: proc() -> string {
    return "Add defer free() immediately after allocation"
}