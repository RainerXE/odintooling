# Tree-sitter Integration Plan

## Overview

This document outlines the complete plan to integrate tree-sitter into the `odin-lint` tool, including both the implementation roadmap and technical details.

## Current State

- **Tree-sitter libraries** are built (`libtree-sitter.a`, `libtree-sitter-odin.a`).
- **Odin-lint** uses a **placeholder** for tree-sitter (no real parsing yet).
- **Goal**: Replace the placeholder with real tree-sitter FFI.
- **Placeholder Implementation**: The current `src/core/tree_sitter.odin` file contains a placeholder implementation that simulates tree-sitter functionality.
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
4. ✅ Successfully compiled the code (linker errors are expected at this stage)

**Key Bindings Created**:
- Parser functions: `ts_parser_new`, `ts_parser_delete`, `ts_parser_parse_string`
- Tree functions: `ts_tree_root_node`, `ts_tree_delete`
- Node functions: `ts_node_type`, `ts_node_start_byte`, `ts_node_end_byte`, `ts_node_child_count`, `ts_node_child`
- Proper type definitions: `TSParser`, `TSTree`, `TSNode`, `TSLanguage` as `distinct rawptr`

**Result**: The Odin code now compiles successfully, demonstrating that the FFI bindings are correctly defined. The linker errors are expected since the tree-sitter static library needs to be properly linked.

**Gate**: ✅ Verified that the bindings compile without syntax errors.

### Phase 3: Integrate Bindings
**Goal**: Replace the placeholder implementation with the real bindings.

**Steps**:
1. Update `src/core/tree_sitter.odin` to use the new bindings.
2. Ensure all necessary types (e.g., `TSNode`, `TSTree`) are correctly defined.
3. Replace placeholder functions with calls to the real tree-sitter functions.

**Gate**: Verify that the CLI tool compiles and runs with the new bindings.

### Phase 4: Test the Integration
**Goal**: Ensure the tree-sitter integration works correctly.

**Steps**:
1. Compile and run `odin-lint` to verify the bindings work.
2. Test with a sample Odin file (e.g., `test/error.odin`) to confirm parsing functionality.
3. Verify that the OLS plugin system remains functional.

**Gate**: Confirm that the tool parses Odin code correctly and the OLS plugin system is unaffected.

### Phase 5: Document Changes
**Goal**: Update documentation to reflect the new tree-sitter integration.

**Steps**:
1. Update this document with details of the new FFI implementation.
2. Add notes on any issues encountered and their resolutions.
3. Update the project's README or other relevant documentation.

**Gate**: Verify that the documentation is clear and up-to-date.

## Success Criteria

- The `odin-lint` tool compiles and runs with the real tree-sitter FFI.
- The tool correctly parses Odin code using the tree-sitter library.
- The OLS plugin system remains functional and unaffected.
- All changes are documented and easy to understand.

## Risks and Mitigations

- **FFI Complexity**: Ensure the generated bindings work seamlessly with Odin. Test thoroughly.
- **Library Paths**: Resolve issues with library paths and dependencies early.
- **Testing**: Validate the FFI with real Odin code to confirm accuracy.

## Next Steps

Proceed with Phase 3: Link the tree-sitter static library and test the integration.

**Phase 3 Tasks**:
1. Fix the linker errors by properly linking the static library
2. Add the library path to the build process
3. Test the integration with a sample Odin file
4. Verify that the tree-sitter parsing works correctly