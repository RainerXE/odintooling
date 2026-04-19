/*
	odin-lint MCP Server
	File: src/mcp/main.odin

	Exposes odin-lint analysis as MCP tools for Claude Code and other
	MCP clients. Built as a standalone executable with pure Odin — no
	Node.js or external runtime required.

	Build:
	    ./scripts/build_mcp.sh  →  artifacts/odin-lint-mcp

	Claude Code registration (~/.claude/mcp_servers.json or project .mcp.json):
	    {
	      "mcpServers": {
	        "odin-lint": {
	          "command": "/path/to/artifacts/odin-lint-mcp",
	          "args": []
	        }
	      }
	    }

	Tools exposed (Tier 1 — lint):
	    lint_file            — run all rules on a file, return diagnostics JSON
	    lint_snippet         — run all rules on in-memory source text
	    lint_fix             — return proposed fixes for a file (no disk writes)
	    run_lint_denoise     — structured fix objects for AI fix loop

	Tools exposed (Tier 2 — code graph, requires --export-symbols first):
	    get_symbol           — symbol lookup in code graph
	    export_symbols       — run DNA export pipeline, write graph db + symbols.json
	    get_dna_context      — callers + callees + memory role for a proc
	    get_impact_radius    — transitive impact analysis
	    find_allocators      — all allocator-role procedures
	    find_all_references  — all call sites for a symbol (rename foundation)
*/
package mcp_server

import "core:fmt"
import "core:os"

import mcp  "../../vendor/odin-mcp"
import core "../core"

// Package-level tree-sitter parser — initialised once in main, reused across all tool calls.
_ts_parser: core.TreeSitterASTParser
_ts_ready:  bool

main :: proc() {
    p, ok := core.initTreeSitterParser()
    if !ok {
        fmt.eprintln("odin-lint-mcp: failed to initialise tree-sitter parser")
        os.exit(1)
    }
    _ts_parser = p
    _ts_ready  = true

    s: mcp.MCPServer
    mcp.server_init(&s, "odin-lint", core.ODIN_LINT_VERSION)

    // Tier 1 — lint tools
    mcp.server_register_tool(&s, make_lint_file_tool())
    mcp.server_register_tool(&s, make_lint_snippet_tool())
    mcp.server_register_tool(&s, make_lint_fix_tool())
    mcp.server_register_tool(&s, make_run_lint_denoise_tool())

    // Tier 2 — code graph tools (require --export-symbols first)
    mcp.server_register_tool(&s, make_get_symbol_tool())
    mcp.server_register_tool(&s, make_export_symbols_tool())
    mcp.server_register_tool(&s, make_get_dna_context_tool())
    mcp.server_register_tool(&s, make_get_impact_radius_tool())
    mcp.server_register_tool(&s, make_find_allocators_tool())
    mcp.server_register_tool(&s, make_find_all_references_tool())

    mcp.server_run(&s) // blocks until stdin EOF
}
