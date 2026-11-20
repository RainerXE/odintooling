# olt 0.98.5 — release notes

> Released 2026-11-21. A feature release: a stable lint channel for repair harnesses, a
> self-contained map of the code graph, `C040` for frees that do nothing, and MCP access to
> both the map and the exact lint shape.

## What changed

### The lint channel

`--format lint` emits one JSON array on stdout with exactly seven keys per finding:

```json
[{"file": "src/x.odin", "line": 12, "col": 5,
  "severity": "warning", "code": "C001",
  "message": "…", "symbol": "main"}]
```

`code` is the stable rule id (`C001`, `C040`, …), so a harness can histogram findings per attempt
and promote a code later without matching prose. `symbol` is the enclosing procedure, or empty for
a file-scope finding. `--format json` keeps its existing keys and adds `code`, `severity`, `col`
and `symbol` alongside them.

The same exact shape is available over MCP. `lint_file`, `lint_snippet` and `lint_workspace` accept
`format: "lint"`; the default `format: "full"` keeps the existing MCP payload with `rule_id`,
`error_class`, `tier`, `column` and fix details. An unknown format returns an `Invalid_Params`
error naming the valid choices.

### `olt floorplan`

`olt floorplan` reads an existing graph and writes `.codegraph/floorplan.html`:

```bash
olt src/ --export-symbols
olt floorplan
```

The result is one self-contained HTML file with embedded CSS, JavaScript and graph data. It has
package rooms and file cards, internal package-import edges, search, file and symbol details,
callers and callees, lint findings, and a Boundary view for `foreign import` paths, `system:`
libraries, external collections and unresolved calls. There is no server, no network and no source
body embedded.

Options: `--db <path>`, `--out <path>`, `--title <text>`, `--open`, and `--json` to print the map
data instead of writing HTML. The map is deterministic; it does not use an LLM to name components.

C/C++ source is not indexed yet. Native and system imports are shown as the exact boundary the Odin
graph can see, but C definitions, headers and the C call graph are not included.

### MCP access to the map

The graph tools now include:

- **`get_floorplan_data`** — returns the same JSON dataset as `olt floorplan --json`. Read-only.
- **`generate_floorplan`** — writes the HTML map and returns its path, byte size, schema version,
  summary and stale-file marker.

Neither tool exports the graph automatically or opens a browser. Call `export_symbols` first when
the graph is missing; the error says so.

### `C040` and allocator facts

`C040` reports `delete`/`free` on memory owned by `context.temp_allocator` or an arena. The free
reads as cleanup but changes nothing: the allocator releases the memory wholesale.

The ownership analysis also got stricter:

- allocator arguments for `make`/`new`/`new_clone`/`mem.*` are taken by position instead of matching
  any argument that contains “allocator” or “arena”;
- explicit and aliased arenas are recorded as `arena`, so C001, C040 and memory roles agree;
- length constants such as `ARENA_SIZE` are no longer misclassified as custom allocators.

`ODIN_ANALYSIS_VERSION` is 9, so an existing graph is re-indexed on the next export.

## Upgrading

- Existing commands and `--format json`/`--format sarif` consumers are unchanged; the new JSON
  fields are additive.
- Older graphs rebuild automatically on the next `--export-symbols` run because the analysis
  version changed. Run that once if you use C040, C202, ownership data or `olt floorplan`.
- `olt floorplan` needs an exported graph; it does not create one.

## Known limits

- C/C++ source and C call edges are outside the graph. `olt floorplan` shows the FFI boundary, not
  the implementation behind it.
- The map is a snapshot. If a source file changed after export, the CLI prints a stale note and the
  HTML shows a banner; re-run the export for current edges.
- `format: "lint"` is opt-in. The default MCP lint payload remains the richer `full` shape.
- The floorplan map is a single HTML file; very large monorepos may produce a large embedded dataset.

## Release files

Each platform has one archive, `olt-0.98.5-<platform>.tar.gz` (macOS arm64, Linux x86_64) or `.zip`
(Windows x86_64), holding `olt`, `olt-mcp` and `olt-lsp`.

## Verified with

- Odin `dev-2026-11`, tree-sitter-odin `v1.3.0`, CodeGraph schema v16.
- macOS: every rule suite, the floorplan suite (24 checks), the MCP suite (131 checks), the
  ownership and `.gitignore` suites, the CodeGraph contract test, and `olt src/` self-lint.
- Linux and Windows builds run through GitHub Actions on the release tag.
