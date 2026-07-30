# Changelog

All notable changes to this project are documented here. Entries start from
this file's introduction — see `git log` for the full pre-changelog history.

## [Unreleased]

### Fixed
- **Crash**: `query_engine.odin`'s `load_query_src` read up to 1024 bytes past
  tree-sitter's capture-name buffers when converting them to Odin strings,
  instead of using the exact length tree-sitter already provides. This was a
  real, build-layout-dependent `SIGSEGV` in the LSP proxy (`olt-lsp`) —
  reproduced live, always crashing in `bytes.index_byte` via
  `strings.truncate_to_byte`, with the length register always exactly 1024.
- CI's macOS build job called `scripts/build_mcp.sh` and `scripts/build_lsp.sh`,
  neither of which exist — every push/tag build was failing at that step.
  `olt-mcp`/`olt-lsp` are now created as symlinks to `olt`, matching the
  argv[0]-dispatch design (and Linux's existing build script).
- `run_c014_tests.sh` / `run_c015_tests.sh`: hardcoded `./artifacts/olt`
  instead of resolving the binary via `_platform.sh`; both silently failed
  with a missing-binary error.
- `comprehensive_odin_test.sh`: a `grep -c ... || echo "0"` pattern produced
  two lines of output on no match, breaking every downstream `-gt 0` check;
  combined with `set -e` this made the script abort after the first clean
  file — confirmed every historical report had been truncated at the same
  point, meaning this script had never completed a full run.
- `test_all_c001_tests.sh`, `test_grammar_completeness.sh`,
  `test_odin_libraries.sh`, `test_ruishin.sh`: all referenced the pre-rename
  `odin-lint` binary name and/or stale hardcoded paths.
- `rule_docs.odin`'s C031/C034 `--explain` text described the flagged pattern
  literally (`panic(...)` / `for v, _ in collection`), which both rules' own
  text-scan matchers then flagged inside olt's own source. Reworded the docs
  (same meaning) rather than changing the matchers.

### Added
- CI now runs all `scripts/run_*.sh` rule-fixture suites plus the MCP and
  config test suites on macOS, not just a 4-line smoke test — a rule
  regression could previously ship silently to a tagged release.

## [0.97.3] - 2026-07-10
Installer fixes and version bump. See `git log v0.97.2..v0.97.3` for detail.
