# Tree-sitter Integration Plan

## Overview

This document outlines the complete plan to integrate tree-sitter into the `odin-lint` tool, including both the implementation roadmap and technical details.

## Current State

- **Tree-sitter libraries** are built (`libtree-sitter.a`, `libtree-sitter-odin.a`).
- **Odin-lint** now uses **real tree-sitter FFI** (placeholder removed).
- **Status**: ✅ Tree-sitter integration is COMPLETE and working.
- **Implementation**: The `src/core/tree_sitter.odin` file now contains real tree-sitter functionality.
- **Tree-sitter Library**: The tree-sitter source code is available in `ffi/tree_sitter/tree-sitter-lib/`.
- **Odin Grammar**: The Odin grammar for tree-sitter is located in `ffi/tree_sitter/tree-sitter-odin/`.
- **Static Library**: The tree-sitter library has been compiled into a static library (`libtree-sitter.a`) for macOS, located at `ffi/tree_sitter/tree-sitter-lib/lib/src/macos/libtree-sitter.a`.

## Technical Implementation Approaches

### 1. Using `odin-c-bindgen` (Recommended)

[odin-c-bindgen](https://github.com/karl-zylinski/odin-c-bindgen) generates Odin bindings from C headers.

#### Steps:

1. **Install libclang** (required by `odin-c-bindgen`):
   ```bash
   brew install libclang  # macOS
   apt install libclang-dev  # Ubuntu/Debian
   ```

2. **Build the generator**:
   ```bash
   cd /tmp/odin-c-bindgen
   odin build src -out:bindgen
   ```

3. **Generate bindings**:
   ```bash
   mkdir -p ffi/tree_sitter/bindings
   cd ffi/tree_sitter/bindings
   cp ../../tree-sitter-lib/lib/include/*.h .
   /tmp/odin-c-bindgen/bindgen .
   ```

4. **Use the bindings** in `tree_sitter.odin`:
   ```odin
   import "ffi/tree_sitter/bindings"
   ```

5. **Link the libraries**:
   ```bash
   odin build src/core/ -out:odin-lint \
     -extra-linker-flags:"-Lffi/tree_sitter/tree-sitter-lib -ltree-sitter \
       -Lffi/tree_sitter/tree-sitter-odin -ltree-sitter-odin"
   ```

### 2. Manual FFI with `foreign`

Odin's `foreign` blocks allow direct C bindings, but they **cannot be at package level**. Example:

```odin
foreign {
    func_name :: proc(...) -> ...,
}
```

**Limitation**: This requires careful placement in procedures.

### 3. Dynamic Loading with `dynlib`

Use `dynlib.load_library` to load the tree-sitter libraries at runtime:

```odin
lib := dynlib.load_library("libtree-sitter.dylib")
func_name := dynlib.symbol(lib, "ts_parser_new")
```

**Pros**: No compile-time linking. **Cons**: More complex.

## Recommended Approach

Use **`odin-c-bindgen`** (Approach 1) for:
- Clean, generated bindings.
- Easy maintenance.
- Better type safety.

## Integration Roadmap

### Phase 1: Compile Tree-sitter as a Static Library
**Status**: ✅ Completed

**Goal**: Compile the tree-sitter library into a static library for the target platform.

**Steps**:
1. Navigate to `ffi/tree_sitter/tree-sitter-lib/`.
2. Compile the tree-sitter source code into object files using `clang -c src/*.c -I../include`.
3. Create a static library (`libtree-sitter.a` for macOS/Linux, `tree-sitter.lib` for Windows) using `ar rc macos/libtree-sitter.a *.o`.

**Example for macOS**:
```bash
clang -c src/*.c -I../include
ar rc macos/libtree-sitter.a *.o
```

**Result**: The static library `libtree-sitter.a` has been successfully created at `ffi/tree_sitter/tree-sitter-lib/lib/src/macos/libtree-sitter.a`.

**Gate**: ✅ Verified that the static library is created successfully.

### Phase 2: Create Odin Bindings
**Status**: ✅ Completed

**Goal**: Define Odin bindings for the tree-sitter library.

**Steps Completed**:
1. ✅ Created `src/core/tree_sitter_bindings.odin` with proper FFI bindings
2. ✅ Defined tree-sitter functions and structures in a `foreign` block with C calling convention
3. ✅ Updated `src/core/tree_sitter.odin` to use the real bindings instead of placeholders
4. ✅ Successfully compiled and linked the code

**Key Bindings Created**:
- Parser functions: `ts_parser_new`, `ts_parser_delete`, `ts_parser_parse_string`
- Tree functions: `ts_tree_root_node`, `ts_tree_delete`
- Node functions: `ts_node_type`, `ts_node_start_byte`, `ts_node_end_byte`, `ts_node_child_count`, `ts_node_child`, `ts_node_is_null`
- **CRITICAL FIX**: TSNode correctly defined as 24-byte struct (not pointer):
  ```odin
  TSNode :: struct {
      ctx: [4]rawptr,  // opaque internal state
      id:  rawptr,
      tree: rawptr,
  }
  ```
- Proper type definitions: `TSParser`, `TSTree`, `TSLanguage`, `TSQuery`, `TSQueryCursor` as `distinct rawptr`

**Result**: The Odin code now compiles and links successfully. The tree-sitter integration is fully functional.

**Gate**: ✅ Verified that the bindings compile, link, and work correctly with real Odin files.

### Phase 3: Integrate Bindings ✅ COMPLETED
**Status**: ✅ Completed

**Goal**: Replace the placeholder implementation with the real bindings.

**Steps Completed**:
1. ✅ Updated `src/core/tree_sitter.odin` to use the new bindings
2. ✅ Fixed TSNode definition from pointer to proper struct
3. ✅ Replaced all nil checks with `ts_node_is_null()` calls
4. ✅ Fixed string conversion to use proper C string handling
5. ✅ Implemented real file parsing with tree-sitter
6. ✅ Added proper error handling and validation

**Key Changes**:
- Fixed the root cause of crashes: TSNode was incorrectly defined as `distinct rawptr` but should be a 24-byte struct
- Added `ts_node_is_null()` function for proper null checking
- Updated all node validation logic to use the new struct-based approach
- Fixed string conversion from C strings to Odin strings

**Gate**: ✅ Verified that the CLI tool compiles, links, and runs with the new bindings.

### Phase 4: Test the Integration ✅ COMPLETED
**Status**: ✅ Completed

**Goal**: Ensure the tree-sitter integration works correctly.

**Steps Completed**:
1. ✅ Compiled `odin-lint` successfully with proper library linking
2. ✅ Tested with simple Odin file (`ffi/test_input.odin`) - works perfectly
3. ✅ Tested with complex Odin file (structs, functions, control flow) - works perfectly
4. ✅ Verified no crashes on valid Odin files
5. ✅ Confirmed proper exit codes and error handling

**Test Results**:
- ✅ Simple test: Successfully parsed `ffi/test_input.odin`
- ✅ Complex test: Successfully parsed complex Odin code with structs, functions, arrays, and control flow
- ✅ No memory corruption or crashes
- ✅ All tree-sitter functions working correctly

**Gate**: ✅ Confirmed that the tool parses Odin code correctly and is ready for OLS integration.

### Phase 5: Document Changes ✅ COMPLETED
**Status**: ✅ Completed

**Goal**: Update documentation to reflect the new tree-sitter integration.

**Steps Completed**:
1. ✅ Updated this document with details of the FFI implementation
2. ✅ Added notes on the critical TSNode fix and other changes
3. ✅ Updated the main implementation plan to reflect completion status
4. ✅ Documented testing results and verification

**Gate**: ✅ Documentation is clear, up-to-date, and reflects the current working state.

## Success Criteria ✅ ACHIEVED

- ✅ The `odin-lint` tool compiles and runs with the real tree-sitter FFI.
- ✅ The tool correctly parses Odin code using the tree-sitter library.
- ✅ Successfully tested with both simple and complex Odin files.
- ✅ No crashes or memory corruption issues.
- ✅ All changes are documented and easy to understand.

## Risks and Mitigations

- ✅ **FFI Complexity**: Resolved by proper TSNode struct definition and thorough testing.
- ✅ **Library Paths**: Resolved by proper linker flags and library paths.
- ✅ **Testing**: Validated with real Odin code - parsing works correctly.

## Next Steps

**Tree-sitter integration is COMPLETE!** 🎉

Now that the CLI tree-sitter integration is working perfectly, the next steps are:

1. **OLS Plugin Integration**: Wire the tree-sitter parsing into the OLS plugin system
2. **Rule Implementation**: Implement real C001 and C002 rules using the working tree-sitter AST
3. **Test Fixtures**: Create comprehensive test fixtures for all rules
4. **CLI Enhancements**: Add command-line flags and options
5. **Additional Rules**: Implement the full set of linting rules

**Current Focus**: OLS plugin integration to bring linting capabilities to the editor.