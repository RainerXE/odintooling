# olt 0.98.2 — release notes

> Released 2026-11-17. A feature release: the code graph gets a CLI, the MCP context tool gets a
> budget, and two kinds of silent gaps now say so. `olt` also gained a self-updater.

## What changed

**Query the graph from the CLI.** `olt symbol <name>`, `olt callers <name>` and `olt refs <name>`
answer from the same tables as the MCP tools and print the same JSON with `--json`, so a consumer
can drop its SQLite coupling and keep its parser. `--db <path>` selects the database. A plain
name that exists in more than one package lists the `package::name` candidates and exits 2
instead of guessing; a missing symbol exits 1.

**The kind vocabulary is documented.** `olt --list-kinds` prints the nine kinds olt writes:
`file`, `function`, `struct`, `union`, `enum`, `enum_member`, `constant`, `variable`, `import`.
Procedures are `function` nodes; `proc` is not a kind. `--db` is now listed in `--help`.

**`olt symbol --json` carries `lint_violations`.** The stored findings for the declaration (leaks,
unchecked errors, deferred-frees) are in the payload, so a repair prompt can see the verifier-backed
signal without a second call.

**Two silent gaps now warn.** `--export-symbols` on a directory with no `*_test.odin` files prints
a note: the graph has no call edges from tests and looks healthy while being half-blind. The query
commands note when an indexed source file changed after the database was built.

**`get_dna_context` takes a `token_budget`.** The callers, callees, allocator variables and
ownership sites are trimmed to fit an approximate token budget (4 characters per token); the proc
header and the ownership summary are always kept, and the payload reports `token_budget`,
`estimated_tokens` and `truncated`.

**`olt update`.** Installs the latest GitHub release over the running binary after verifying the
asset's SHA-256 from the GitHub API. `--check` reports only; `--force` reinstalls the current
release. On macOS the install writes a new inode and renames it into place.

**Install fix.** `olt --install` used to copy the new binary over the old one in place. On Apple
Silicon that can leave the kernel's code-signing cache holding the old hash for the vnode: every
later run is killed with `SIGKILL (Code Signature Invalid)` even though the file itself verifies.
The install now writes a sibling temp file and renames it, and a regression test asserts that a
reinstall changes the inode.

## Upgrading

No graph schema or analysis version change, so existing databases stay valid. `olt update` is
available for the first time in this release, which means 0.98.1 users download this one by hand.

## Known limits

- A qualified name is `package::name` (the package declared by `package <name>`, not the
  directory). An ambiguous name is reported rather than resolved arbitrarily.
- The stale-index note compares indexed files against the export time; a file added after the
  export is not detected until the next export.
- `token_budget` is approximate: it allocates a share of the budget to each list and reports the
  estimate. A tiny budget can be exceeded by the mandatory header.

## Release files

Each platform has one archive, `olt-0.98.2-<platform>.tar.gz` (macOS arm64, Linux x86_64) or `.zip`
(Windows x86_64), holding `olt`, `olt-mcp` and `olt-lsp`.

## Verified with

- Odin `dev-2026-11`, tree-sitter-odin `v1.3.0`, CodeGraph `1.6.2` (schema v16).
- macOS: the graph-query suite, the install suite, every rule suite, the MCP and config tests, the
  ownership and `.gitignore` suites and the CodeGraph contract test. The macOS and Linux builds and
  their suites run on GitHub Actions; Windows builds and passes the smoke checks there.
