// main.odin — Unified olt entry point with argv[0] dispatch.
// A single binary serves all three interfaces:
//   invoked as "ols" or "olt-lsp"  → LSP proxy mode (wraps vanilla OLS)
//   invoked as "olt-mcp"           → MCP server mode (stdio JSON-RPC)
//   olt mcp / olt lsp subcommand   → explicit mode selection
//   default                        → CLI linter mode
//
// Symlinks created by `olt --install` enable the busybox pattern so editors
// and MCP clients can point to their expected binary name without any changes.
package main

import "core:fmt"
import "core:os"
import "core:strings"

import core "./core"
import mcp  "./mcp"
import lsp  "./lsp"

main :: proc() {
    // argv[0] dispatch — check how we were invoked.
    exe := _exe_name()

    if strings.contains(exe, "lsp") || exe == "ols" {
        lsp.lsp_run()
        return
    }
    if strings.contains(exe, "mcp") {
        mcp.mcp_run()
        return
    }

    // Explicit subcommands.
    if len(os.args) > 1 {
        switch os.args[1] {
        case "mcp":   mcp.mcp_run();                   return
        case "lsp":   lsp.lsp_run();                   return
        case "setup": os.exit(core.run_setup_command())
        case "init":  os.exit(core.run_local_init())
        }
    }

    // Default: CLI mode.
    os.exit(core.cli_main())
}

// _exe_name returns just the base filename of os.args[0] without path.
@(private="file")
_exe_name :: proc() -> string {
    if len(os.args) == 0 { return "olt" }
    arg := os.args[0]
    // Strip directory prefix.
    for i := len(arg) - 1; i >= 0; i -= 1 {
        if arg[i] == '/' || arg[i] == '\\' {
            arg = arg[i+1:]
            break
        }
    }
    // Strip .exe suffix on Windows.
    if strings.has_suffix(arg, ".exe") {
        arg = arg[:len(arg)-4]
    }
    return arg
}
