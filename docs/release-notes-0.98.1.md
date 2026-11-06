# olt 0.98.1 — release notes

> Released 2026-11-06. A patch release: C001 reports more. Nothing else changes.

## What changed

**C001 reports an allocation that nothing is bound to and nothing frees.** The rule used to look only for `x := make(...)`. It
now also reports, for the default allocator and a parameter allocator:

- `_ = len(make([]u8, 10))` and `return len(make([]u8, 10))`: the result is measured, then dropped.
- A bare `make([]u8, 10)` statement.
- `n := len(make([]u8, 10))`: the variable holds a number, not the slice.

The report reads "Allocation result is dropped — nothing can free it". It comes from the same ownership analysis as the graph, so
it is quiet where that analysis sees the memory taken care of: temp-allocator and arena memory, results that are returned, stored,
appended or handed to a procedure that may keep them, `*_init` procedures, and lines marked `// olt:ignore C001`.

Measured against 0.98.0 on Odin's own `core` and `vendor` and on eight other Odin projects, the number of C001 reports is the same.

## Upgrading

Expect a few new C001 reports in code that drops an allocation. The graph database is unchanged (the analysis version stays 8), so
nothing is re-indexed.

## Known limits

- **A call to your own procedure that only reads its argument is not reported.** `reads_only(make(...))` looks like "handed on" to
  the lint rule, which analyses one file at a time. The graph does mark it `leak_candidate`.

## Release files

Each platform has one archive, `olt-0.98.1-<platform>.tar.gz` (macOS arm64, Linux x86_64) or `.zip` (Windows x86_64), holding `olt`,
`olt-mcp` and `olt-lsp`.

## Verified with

- Odin `dev-2026-10`, tree-sitter-odin `v1.3.0`, CodeGraph `1.6.2` (schema v16).
- macOS: every rule suite, the MCP and config tests, the ownership and `.gitignore` suites and the CodeGraph contract test. The
  macOS and Linux builds and their suites run on GitHub Actions; Windows builds and passes the smoke checks there.
