# C Interface Review for odin-lint

This document tracks C interfaces used in odin-lint for FFI (Foreign Function Interface) integration.

## Tree-Sitter Integration

### Purpose
- Parse Odin source code into Abstract Syntax Trees (AST)
- Enable semantic analysis for linting rules
- Provide foundation for AI/coding agent integration

### C Headers
- `ffi/tree_sitter/tree_sitter.h` - Main tree-sitter C API
- Tree-sitter Odin grammar (via git submodule)

### Odin FFI Wrappers
- `src/core/tree_sitter.odin` - Main FFI bindings
- `src/ast/tree_sitter_wrapper.odin` - AST utilities (future)

### Review Process
1. Document all C functions used in FFI
2. Review memory management requirements
3. Test FFI bindings with sample Odin code
4. Validate AST structure matches expectations

### Current Status
- ✅ FFI directory structure created
- ⏳ Tree-sitter Odin submodule to be added
- ⏳ FFI bindings implementation in progress
- ⏳ AST conversion utilities needed

### Safety Considerations
- Memory management: Ensure proper cleanup of tree-sitter resources
- Error handling: Validate all FFI calls and handle errors gracefully
- Thread safety: Tree-sitter is not thread-safe by default

### Testing Strategy
- Test with existing test fixtures
- Validate AST structure for known Odin patterns
- Check memory usage and cleanup
- Test error conditions and edge cases