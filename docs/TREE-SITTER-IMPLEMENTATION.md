# Tree-sitter Implementation Guide

This document outlines the steps to implement real tree-sitter integration in `odin-lint`.

## Current State

- **Tree-sitter libraries** are built (`libtree-sitter.a`, `libtree-sitter-odin.a`).
- **Odin-lint** uses a **placeholder** for tree-sitter (no real parsing yet).
- **Goal**: Replace the placeholder with real tree-sitter FFI.

## Approaches

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

Odin’s `foreign` blocks allow direct C bindings, but they **cannot be at package level**. Example:

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

## Files

- `ffi/tree_sitter/tree-sitter-lib/`: Tree-sitter core library.
- `ffi/tree_sitter/tree-sitter-odin/`: Odin grammar for tree-sitter.
- `src/core/tree_sitter_real.odin`: Real FFI implementation (WIP).
- `build_tree_sitter.sh`: Script to build tree-sitter libraries.

## Next Steps

1. Generate bindings with `odin-c-bindgen`.
2. Replace the placeholder in `tree_sitter.odin`.
3. Test with real Odin files.

## References

- [odin-c-bindgen](https://github.com/karl-zylinski/odin-c-bindgen)
- [Odin FFI Documentation](https://odin-lang.org/news/binding-to-c/)
- [Clay FFI Example](https://deepwiki.com/nicbarker/clay/6.1-odin-bindings)
