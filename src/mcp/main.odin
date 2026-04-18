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

	Tools exposed:
	    lint_file      — run all rules on a file, return diagnostics JSON
	    lint_snippet   — run all rules on in-memory source text
	    lint_fix       — return proposed fixes for a file (no disk writes)
	    get_symbol     — [stub] symbol lookup via OLS (M5.6)
	    export_symbols — [stub] symbols.json export (M5.6)
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

    mcp.server_register_tool(&s, make_lint_file_tool())
    mcp.server_register_tool(&s, make_lint_snippet_tool())
    mcp.server_register_tool(&s, make_lint_fix_tool())
    mcp.server_register_tool(&s, make_get_symbol_tool())
    mcp.server_register_tool(&s, make_export_symbols_tool())

    mcp.server_run(&s) // blocks until stdin EOF
}
