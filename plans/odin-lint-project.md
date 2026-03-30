# Odin-Lint Project Overview

## Architecture

### 1. Odin-Lint Tool (`src/`)
The core linting tool with two modes:

#### CLI Mode
- **Purpose**: Standalone command-line tool for linting Odin code.
- **Build**: Compiled via `build.sh` → produces a standalone binary.
- **Usage**:
  ```sh
  odin-lint <file.odin> [--ast] [--lsp]
  ```

#### Plugin Mode
- **Purpose**: Dynamically loadable library for integration with OLS (Odin Language Server).
- **Build**: Compiled into a `.dylib` (macOS) or `.so` (Linux) → loaded by OLS at runtime.
- **Usage**:
  - OLS loads the plugin to provide real-time linting in editors.

### 2. Tree-sitter Integration (`ffi/tree_sitter/`)
- **Purpose**: Parses Odin code into an Abstract Syntax Tree (AST) for analysis.
- **Components**:
  - `tree-sitter-odin`: Odin grammar for Tree-sitter.
  - `tree-sitter-lib`: Core Tree-sitter library.
- **Usage**:
  - Used by both CLI and plugin modes to analyze code structure.
  - Enables advanced linting rules (e.g., C001, C002).

### 3. OLS (Odin Language Server) (`vendor/ols/`)
- **Purpose**: Modified version of the Odin Language Server with plugin support.
- **Modifications**:
  - Added dynamic plugin loading (`plugin_manager.odin`, `plugin_dynamic.odin`).
  - Supports loading `odin-lint` as a plugin for LSP integration.
- **Usage**:
  - Provides editor integration (VS Code, etc.) with real-time linting.

## Dependencies

### Core Files (`src/core/`)
- `main.odin`: Entry point for CLI mode.
- `lsp_server.odin`: LSP server logic (for plugin mode).
- `ast.odin`: AST utilities.
- `c001.odin`, `c002.odin`: Linting rules.
- `odin_lint_plugin.odin`: Plugin interface for OLS.

### Tree-sitter (`ffi/tree_sitter/`)
- `tree-sitter-odin`: Odin grammar.
- `tree-sitter-lib`: Core Tree-sitter library.

### OLS (`vendor/ols/`)
- `src/server/plugin_manager.odin`: Manages dynamic plugins.
- `src/server/plugin_dynamic.odin`: Loads plugins at runtime.

## Build Process

### CLI Mode
```sh
# Build the standalone binary
odin build src/core/ -out:odin-lint

# Run linting
./odin-lint path/to/file.odin
```

### Plugin Mode
```sh
# Build the dynamic library
odin build src/core/ -build-mode:shared -out:odin_lint_plugin

# OLS loads the plugin automatically
```

## Current Issues
- Syntax errors in `lsp_server.odin` and `odin_lint_plugin.odin`.
- Merge conflicts (e.g., `=======` markers).
- Build failures due to unresolved dependencies.

## Next Steps
1. Fix syntax errors in core files.
2. Test Tree-sitter integration.
3. Validate CLI and plugin modes.
