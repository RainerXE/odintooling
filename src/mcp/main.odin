/*
	olt MCP Server
	File: src/mcp/main.odin

	Exposes olt analysis as MCP tools for Claude Code and other
	MCP clients. Built as a standalone executable with pure Odin — no
	Node.js or external runtime required.

	Build:
	    ./scripts/build_mcp.sh  →  artifacts/olt-mcp

	Claude Code registration (~/.claude/mcp_servers.json or project .mcp.json):
	    {
	      "mcpServers": {
	        "olt": {
	          "command": "/path/to/artifacts/olt-mcp",
	          "args": []
	        }
	      }
	    }

	Tools exposed (Tier 1 — lint):
	    lint_file            — run all rules on a file, return diagnostics JSON
	    lint_snippet         — run all rules on in-memory source text
	    lint_fix             — return proposed fixes for a file (no disk writes)
	    run_lint_denoise     — structured fix objects for AI fix loop
	    lint_workspace       — batch lint an entire directory, return all diagnostics
	    list_rules           — return the full rule catalog as JSON
	    run_odin_check       — run `odin check` and return compiler diagnostics as JSON

	Tools exposed (Tier 2 — code graph, requires --export-symbols first):
	    get_symbol           — symbol lookup in code graph
	    export_symbols       — run DNA export pipeline, write graph db + symbols.json
	    get_dna_context      — callers + callees + memory role for a proc
	    get_impact_radius    — transitive impact analysis
	    find_allocators      — all allocator-role procedures
	    find_all_references  — all call sites for a symbol (rename foundation)
	    get_callers          — all direct callers of a proc (LSP incoming calls)
	    get_callees          — all direct callees of a proc (LSP outgoing calls)
*/
package mcp_server

import "core:fmt"
import "core:os"

import mcp  "../../vendor/odin-mcp/mcp"
import core "../core"

// Package-level tree-sitter parser — initialised once in main, reused across all tool calls.
_ts_parser: core.TreeSitterASTParser
_ts_ready:  bool

// mcp_run is the MCP server entry point, called from src/main.odin.
mcp_run :: proc() {
    p, ok := core.initTreeSitterParser()
    if !ok {
        fmt.eprintln("olt: MCP mode: failed to initialise tree-sitter parser")
        os.exit(1)
    }
    _ts_parser = p
    _ts_ready  = true

    s: mcp.MCPServer
    mcp.server_init(&s, "olt", core.ODIN_LINT_VERSION)

    // Tier 1 — lint tools
    mcp.server_register_tool(&s, make_lint_file_tool())
    mcp.server_register_tool(&s, make_lint_snippet_tool())
    mcp.server_register_tool(&s, make_lint_fix_tool())
    mcp.server_register_tool(&s, make_run_lint_denoise_tool())
    mcp.server_register_tool(&s, make_lint_workspace_tool())
    mcp.server_register_tool(&s, make_list_rules_tool())
    mcp.server_register_tool(&s, make_run_odin_check_tool())

    // Tier 2 — code graph tools (require --export-symbols first)
    mcp.server_register_tool(&s, make_get_symbol_tool())
    mcp.server_register_tool(&s, make_export_symbols_tool())
    mcp.server_register_tool(&s, make_get_dna_context_tool())
    mcp.server_register_tool(&s, make_get_impact_radius_tool())
    mcp.server_register_tool(&s, make_find_allocators_tool())
    mcp.server_register_tool(&s, make_find_all_references_tool())
    mcp.server_register_tool(&s, make_rename_symbol_tool())
    mcp.server_register_tool(&s, make_get_callers_tool())
    mcp.server_register_tool(&s, make_get_callees_tool())
    mcp.server_register_tool(&s, make_search_symbols_tool())

    mcp.server_run(&s) // blocks until stdin EOF
}
