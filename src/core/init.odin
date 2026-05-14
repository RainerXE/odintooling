// init.odin — olt setup (system wizard) and olt init (local project config).
//
// olt setup  — full first-run wizard: OLS detection, install + symlinks.
//              Writes ~/.config/olt/setup_done on completion.
// olt init   — creates olt.toml in the current directory.
//              Checks for setup_done marker first; if missing, runs setup.
// --install  — re-run only the install step (useful after a rebuild).
package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// Public entry points
// =============================================================================

// run_setup_command is the full first-run wizard. Returns exit code.
// Invoked by: `olt setup`  and  `olt --init` (backward compat alias).
run_setup_command :: proc() -> int {
	fmt.printfln("olt %s  —  Setup", OLT_VERSION)
	fmt.println()

	// ── Step 1: OLS ──────────────────────────────────────────────────────────
	_init_header(1, 3, "OLS (Odin Language Server)")
	_init_ols_step()
	fmt.println()

	// ── Step 2: Install ──────────────────────────────────────────────────────
	_init_header(2, 3, "Install")
	_install_step()
	fmt.println()

	// ── Step 3: MCP ──────────────────────────────────────────────────────────
	_init_header(3, 3, "MCP Integration")
	_init_mcp_step()
	fmt.println()

	_write_setup_marker()
	fmt.println("Setup complete.")
	fmt.println("Run 'olt init' in any Odin project to create a local olt.toml.")
	return 0
}

// run_init_command is the backward-compat alias for run_setup_command.
// Invoked by: `olt --init`
run_init_command :: proc() -> int {
	return run_setup_command()
}

// run_local_init creates olt.toml in the current directory.
// Invoked by: `olt init`
// If setup has not been run, informs the user and offers to run it first.
run_local_init :: proc() -> int {
	if !_setup_done() {
		fmt.println("olt setup has not been run yet.")
		fmt.println("It configures OLS and installs olt system-wide — needed for full functionality.")
		fmt.println()
		fmt.print("Run 'olt setup' now? [Y/n]: ")
		if _yn_default_yes() {
			fmt.println()
			code := run_setup_command()
			if code != 0 { return code }
			fmt.println()
		} else {
			fmt.println("Skipped — you can run 'olt setup' at any time.")
			fmt.println()
		}
	}

	fmt.printfln("olt %s  —  Project init", OLT_VERSION)
	fmt.println()
	_init_config_step("")
	return 0
}

// run_install_command re-runs only the install step. Returns exit code.
// Invoked by: `olt --install`
run_install_command :: proc() -> int {
	fmt.printfln("olt %s  —  Install", OLT_VERSION)
	fmt.println()
	_install_step()
	return 0
}

// =============================================================================
// Setup marker
// =============================================================================

@(private = "file")
_setup_marker_path :: proc() -> string {
	home, ok := os.lookup_env_alloc("HOME", context.temp_allocator)
	if !ok || home == "" { return "" }
	return strings.join([]string{home, ".config", "olt", "setup_done"}, "/",
		allocator = context.temp_allocator)
}

@(private = "file")
_setup_done :: proc() -> bool {
	path := _setup_marker_path()
	return path != "" && os.is_file(path)
}

@(private = "file")
_write_setup_marker :: proc() {
	path := _setup_marker_path()
	if path == "" { return }
	// Ensure ~/.config/olt/ exists.
	last_slash := strings.last_index(path, "/")
	if last_slash > 0 {
		dir := path[:last_slash]
		if !os.is_dir(dir) {
			state, _, _, err := os.process_exec(
				os.Process_Desc{command = []string{"mkdir", "-p", dir}},
				context.allocator,
			)
			if err != nil || !state.success { return }
		}
	}
	_ = os.write_entire_file_from_string(path, OLT_VERSION)
}

// =============================================================================
// Step implementations
// =============================================================================

@(private = "file")
_init_ols_step :: proc() -> (ols_path: string) {
	// Try both common names: 'ols' (build-from-source) and 'ols_lsp' (Homebrew).
	found := _which("ols")
	if found == "" { found = _which("ols_lsp") }

	if found != "" {
		fmt.printfln("  Found OLS: %s", found)
		fmt.print("  Use a different path? [y/N]: ")
		if _yn_default_no() {
			fmt.print("  Path: ")
			return _readline()
		}
		return found
	}

	fmt.println("  OLS not found in PATH.")
	fmt.println("  OLS provides type-checking and completions in your editor.")
	fmt.println()
	fmt.println("  Install options:")
	fmt.println("    Homebrew:         brew install ols      (binary: ols_lsp)")
	fmt.println("    Build from source: https://github.com/DanielGavin/ols  (binary: ols)")
	fmt.println()
	fmt.println("  Tip: run 'which ols_lsp' or 'which ols' to find the installed path.")
	fmt.println()
	fmt.print("  Enter path to OLS binary, or leave blank to skip: ")
	entered := _readline()
	if entered != "" && os.is_file(entered) {
		fmt.printfln("  Will write ols_path = \"%s\" to olt.toml.", entered)
		return entered
	}
	if entered != "" {
		fmt.printfln("  Warning: %s does not exist — skipping ols_path.", entered)
	} else {
		fmt.println("  Skipped — set ols_path in olt.toml later if needed.")
	}
	return ""
}

@(private = "file")
_init_config_step :: proc(ols_path: string) {
	if os.is_file("olt.toml") {
		fmt.println("  olt.toml already exists — skipping.")
		return
	}

	fmt.print("  Create olt.toml in current directory? [Y/n]: ")
	if !_yn_default_yes() {
		fmt.println("  Skipped.")
		return
	}

	fmt.println()
	fmt.println("  Rule profile:")
	fmt.println("    1  basic     — core correctness rules (C001/C002/C011/C101/C201)")
	fmt.println("    2  standard  — + style + stdlib safety  [recommended]")
	fmt.println("    3  full      — + all opt-in naming and Go-migration rules")
	fmt.print("  Choice [2]: ")
	profile := _readline()
	if profile == "" { profile = "2" }

	content := _build_toml(profile, ols_path)
	defer delete(content)

	if err := os.write_entire_file("olt.toml", transmute([]u8)content); err != nil {
		fmt.printfln("  ✗  Failed to write olt.toml: %v", err)
	} else {
		fmt.println("  ✓  Created olt.toml")
	}
}

@(private = "file")
_install_step :: proc() {
	home, home_ok := os.lookup_env_alloc("HOME", context.allocator)
	defer if home_ok { delete(home) }
	if !home_ok || home == "" {
		fmt.println("  HOME is not set — cannot determine install directory.")
		return
	}

	bin_dir     := _own_bin_dir()
	abs_bin_dir := _resolve_path(bin_dir)
	defer delete(abs_bin_dir)

	olt_src := strings.join([]string{abs_bin_dir, "olt"}, "/")
	defer delete(olt_src)

	dst_dir := strings.join([]string{home, ".local", "bin"}, "/")
	defer delete(dst_dir)

	fmt.printfln("  Source:  %s", olt_src)
	fmt.printfln("  Target:  %s/", dst_dir)
	fmt.println()

	if !os.is_file(olt_src) {
		fmt.printfln("  ✗  olt binary not found at %s — build it first.", olt_src)
		return
	}

	if !os.is_dir(dst_dir) {
		state, _, _, err := os.process_exec(
			os.Process_Desc{command = []string{"mkdir", "-p", dst_dir}},
			context.allocator,
		)
		if err != nil || !state.success {
			fmt.printfln("  ✗  Cannot create %s", dst_dir)
			return
		}
	}

	// Install the olt binary.
	fmt.print("  Install olt binary? [Y/n]: ")
	if _yn_default_yes() {
		olt_dst := strings.join([]string{dst_dir, "olt"}, "/")
		defer delete(olt_dst)
		_ = os.remove(olt_dst)
		state, _, _, err := os.process_exec(
			os.Process_Desc{command = []string{"cp", olt_src, olt_dst}},
			context.allocator,
		)
		if err != nil || !state.success {
			fmt.println("  ✗  olt")
		} else {
			fmt.println("  ✓  olt")
		}
	}

	// Symlinks — asked separately.
	fmt.println()
	fmt.println("  Symlinks (all point to olt, enable argv[0] mode dispatch):")
	fmt.println()

	olt_dst := strings.join([]string{dst_dir, "olt"}, "/")
	defer delete(olt_dst)

	_ask_symlink(dst_dir, olt_dst, "ols",
		"IDE OLS integration — point your editor here instead of vanilla OLS")
	_ask_symlink(dst_dir, olt_dst, "olt-lsp",
		"Backward-compatible LSP binary name")
	_ask_symlink(dst_dir, olt_dst, "olt-mcp",
		"Backward-compatible MCP binary name")

	// PATH status.
	fmt.println()
	path_val, path_ok := os.lookup_env_alloc("PATH", context.allocator)
	defer if path_ok { delete(path_val) }
	if path_ok && strings.contains(path_val, dst_dir) {
		fmt.printfln("  %s is in PATH ✓", dst_dir)
	} else {
		fmt.printfln("  %s is NOT in PATH", dst_dir)
		fmt.println("  Add this to your shell profile (~/.zshrc or ~/.bashrc):")
		fmt.printfln(`    export PATH="%s:$PATH"`, dst_dir)
	}
}

@(private = "file")
_ask_symlink :: proc(dst_dir, target, link_name, description: string) {
	link_path := strings.join([]string{dst_dir, link_name}, "/")
	defer delete(link_path)
	fmt.printfln("  %s — %s", link_name, description)
	fmt.printf("    Install %s → olt? [Y/n]: ", link_name)
	if !_yn_default_yes() {
		fmt.println("    Skipped.")
		return
	}
	_ = os.remove(link_path)
	state, _, _, err := os.process_exec(
		os.Process_Desc{command = []string{"ln", "-sf", target, link_path}},
		context.allocator,
	)
	if err != nil || !state.success {
		fmt.printfln("    ✗  %s", link_name)
	} else {
		fmt.printfln("    ✓  %s → olt", link_name)
	}
}

// =============================================================================
// Helpers
// =============================================================================

@(private = "file")
_init_header :: proc(step, total: int, name: string) {
	fmt.printfln("--- %d/%d  %s", step, total, name)
	fmt.println()
}

@(private = "file")
_readline :: proc() -> string {
	buf: [512]u8
	n, _ := os.read(os.stdin, buf[:])
	if n <= 0 { return "" }
	return strings.clone(strings.trim(string(buf[:n]), " \t\r\n"))
}

@(private = "file")
_yn_default_yes :: proc() -> bool {
	ans := _readline()
	defer delete(ans)
	return !strings.equal_fold(ans, "n") && !strings.equal_fold(ans, "no")
}

@(private = "file")
_yn_default_no :: proc() -> bool {
	ans := _readline()
	defer delete(ans)
	return strings.equal_fold(ans, "y") || strings.equal_fold(ans, "yes")
}

@(private = "file")
_which :: proc(name: string) -> string {
	when ODIN_OS == .Windows {
		// 'where' may return multiple lines; take the first.
		state, stdout, _, err := os.process_exec(
			os.Process_Desc{command = []string{"where", name}},
			context.allocator,
		)
		defer delete(stdout)
		if err != nil || !state.success { return "" }
		result := string(stdout)
		if nl := strings.index(result, "\n"); nl > 0 { result = result[:nl] }
		return strings.clone(strings.trim(result, " \t\r\n"))
	} else {
		state, stdout, _, err := os.process_exec(
			os.Process_Desc{command = []string{"which", name}},
			context.allocator,
		)
		defer delete(stdout)
		if err != nil || !state.success { return "" }
		return strings.clone(strings.trim(string(stdout), " \t\r\n"))
	}
}

@(private = "file")
_own_bin_dir :: proc() -> string {
	if len(os.args) == 0 { return "." }
	arg0 := os.args[0]
	if !strings.contains(arg0, "/") {
		// Invoked by name from PATH — resolve the actual binary location.
		resolved := _which(arg0)
		defer delete(resolved)
		if resolved != "" { return strings.clone(filepath_dir(resolved)) }
		// Dev-mode fallback: cwd contains an artifacts/ build output.
		if os.is_dir("artifacts") { return "artifacts" }
		return "."
	}
	return filepath_dir(arg0)
}

@(private = "file")
_resolve_path :: proc(p: string) -> string {
	if strings.has_prefix(p, "/") { return strings.clone(p) }
	state, stdout, _, err := os.process_exec(
		os.Process_Desc{command = []string{"pwd"}},
		context.allocator,
	)
	defer delete(stdout)
	if err != nil || !state.success { return strings.clone(p) }
	cwd := strings.trim(string(stdout), " \t\r\n")
	rel := p
	if strings.has_prefix(rel, "./") { rel = rel[2:] }
	return strings.join([]string{cwd, rel}, "/")
}

@(private = "file")
_build_toml :: proc(profile, ols_path: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "# olt.toml — Odin Language Tools project configuration\n")
	strings.write_string(&b, "# Run 'olt --help' to see all available rules.\n\n")

	strings.write_string(&b, "[domains]\n")
	strings.write_string(&b, "ffi       = true  # C011: FFI resource safety\n")
	strings.write_string(&b, "odin_2026 = true  # C009/C010: deprecated API detection\n")

	switch profile {
	case "2", "standard":
		strings.write_string(&b, "stdlib_safety = true  # C029/C033: stdlib allocation safety\n")
	case "3", "full":
		strings.write_string(&b, "stdlib_safety   = true  # C029/C033: stdlib allocation safety\n")
		strings.write_string(&b, "semantic_naming = true  # C012: ownership naming hints\n")
		strings.write_string(&b, "go_migration    = true  # C021-C025: Go→Odin migration traps\n")
	}

	if profile == "3" || profile == "full" {
		strings.write_string(&b, "\n[naming]\n")
		strings.write_string(&b, "c019 = true  # type marker suffixes (_ptr, _slice, _map, …)\n")
		strings.write_string(&b, "c020 = true  # discourage overly short variable names\n")
	}

	if ols_path != "" {
		strings.write_string(&b, "\n[tools]\n")
		fmt.sbprintf(&b, "ols_path = \"%s\"\n", ols_path)
	}

	return strings.clone(strings.to_string(b))
}

// =============================================================================
// MCP registration step — register olt as an MCP server in AI coding tools.
// =============================================================================

// _pjoin joins path parts with "/". Forward slashes work on macOS, Linux, and
// Windows (Win32 APIs and most tools accept them uniformly).
@(private = "file")
_pjoin :: proc(parts: ..string) -> string {
	return strings.join(parts, "/", allocator = context.temp_allocator)
}

// _env_or returns an env var value, or fallback; both are temp-allocated.
@(private = "file")
_env_or :: proc(key, fallback: string) -> string {
	v, ok := os.lookup_env_alloc(key, context.temp_allocator)
	if ok && v != "" { return v }
	return fallback
}

// _get_home returns the user home directory (heap-allocated; caller must delete).
@(private = "file")
_get_home :: proc() -> string {
	when ODIN_OS == .Windows {
		v, ok := os.lookup_env_alloc("USERPROFILE", context.allocator)
		if ok && v != "" { return v }
	}
	v, ok := os.lookup_env_alloc("HOME", context.allocator)
	if ok && v != "" { return v }
	return ""
}

// _find_mcp_bin resolves olt-mcp (heap-allocated; caller must delete).
@(private = "file")
_find_mcp_bin :: proc(home: string) -> string {
	when ODIN_OS == .Windows {
		local := _pjoin(home, ".local", "bin", "olt-mcp.exe")
		if os.is_file(local) { return strings.clone(local) }
	} else {
		local := _pjoin(home, ".local", "bin", "olt-mcp")
		if os.is_file(local) { return strings.clone(local) }
	}
	return _which("olt-mcp")
}

// _which_bool returns true if name is found in PATH.
@(private = "file")
_which_bool :: proc(name: string) -> bool {
	p := _which(name)
	defer delete(p)
	return p != ""
}

// _cline_settings_dir returns the Cline extension settings directory (temp-alloc).
// VS Code stores extension data under OS-specific application-data directories.
@(private = "file")
_cline_settings_dir :: proc(home: string) -> string {
	tail := "Code/User/globalStorage/saoudrizwan.claude-dev/settings"
	when ODIN_OS == .Darwin {
		return _pjoin(home, "Library", "Application Support", tail)
	} else when ODIN_OS == .Windows {
		return _pjoin(_env_or("APPDATA", _pjoin(home, "AppData", "Roaming")), tail)
	} else {
		return _pjoin(_env_or("XDG_CONFIG_HOME", _pjoin(home, ".config")), tail)
	}
}

// _opencode_cfg_dir returns the OpenCode config directory (temp-alloc).
// OpenCode respects $OPENCODE_CONFIG_DIR, otherwise uses ~/.config/opencode.
@(private = "file")
_opencode_cfg_dir :: proc(home: string) -> string {
	v, ok := os.lookup_env_alloc("OPENCODE_CONFIG_DIR", context.temp_allocator)
	if ok && v != "" { return v }
	return _pjoin(home, ".config", "opencode")
}

// _hermes_cfg_dir returns the Hermes Agent config directory (temp-alloc).
@(private = "file")
_hermes_cfg_dir :: proc(home: string) -> string {
	when ODIN_OS == .Windows {
		return _pjoin(_env_or("LOCALAPPDATA", _pjoin(home, "AppData", "Local")), "hermes")
	} else {
		return _pjoin(home, ".hermes")
	}
}

// _mkdir_p creates a directory hierarchy.
@(private = "file")
_mkdir_p :: proc(dir: string) {
	when ODIN_OS == .Windows {
		_, _, _, _ = os.process_exec(os.Process_Desc{command = []string{"cmd", "/c", "md", dir}}, context.allocator)
	} else {
		_, _, _, _ = os.process_exec(os.Process_Desc{command = []string{"mkdir", "-p", dir}}, context.allocator)
	}
}

// _mcp_try checks whether cfg_dir exists.  If not, shows the expected path and
// asks the user to confirm or provide an alternative.
// Returns a heap-allocated directory string (caller must delete), or "" to skip.
@(private = "file")
_mcp_try :: proc(tool_name, cfg_dir: string) -> string {
	if os.is_dir(cfg_dir) { return strings.clone(cfg_dir) }
	fmt.printfln("    Default config location not found: %s", cfg_dir)
	fmt.printf("    Enter %s config directory (or Enter to skip): ", tool_name)
	entered := _readline()
	if entered == "" {
		fmt.println("    Skipped.")
		return ""
	}
	if !os.is_dir(entered) {
		fmt.printfln("    Not a directory: %s — skipping.", entered)
		delete(entered)
		return ""
	}
	return entered
}

@(private = "file")
_init_mcp_step :: proc() {
	home := _get_home()
	defer delete(home)
	if home == "" { return }

	mcp_bin := _find_mcp_bin(home)
	defer delete(mcp_bin)
	if mcp_bin == "" {
		fmt.println("  olt-mcp not found — install step may have been skipped.")
		fmt.println("  Re-run 'olt setup' after installing to register with AI tools.")
		return
	}

	fmt.printfln("  MCP binary: %s", mcp_bin)
	fmt.println()

	found_any := false

	// ── Claude Code ─────────────────────────────────────────────────────────
	if _which_bool("claude") {
		found_any = true
		fmt.println("  Claude Code")
		_mcp_claude(mcp_bin)
		fmt.println()
	}

	// ── Cursor ──────────────────────────────────────────────────────────────
	cursor_home := _pjoin(home, ".cursor")
	if _which_bool("cursor") || os.is_dir(cursor_home) {
		found_any = true
		fmt.println("  Cursor")
		if dir := _mcp_try("Cursor", cursor_home); dir != "" {
			defer delete(dir)
			_mcp_cursor(dir, mcp_bin)
		}
		fmt.println()
	}

	// ── Cline (VS Code extension) ────────────────────────────────────────
	// Detect by settings dir or by the parent extension dir (Cline installed
	// but not yet opened — settings/ won't exist yet).
	cline_settings := _cline_settings_dir(home)
	cline_ext     := filepath_dir(cline_settings)  // saoudrizwan.claude-dev/
	if os.is_dir(cline_settings) || os.is_dir(cline_ext) {
		found_any = true
		fmt.println("  Cline")
		if dir := _mcp_try("Cline", cline_settings); dir != "" {
			defer delete(dir)
			_mcp_cline(dir, mcp_bin)
		}
		fmt.println()
	}

	// ── Codex ────────────────────────────────────────────────────────────
	codex_home := _pjoin(home, ".codex")
	if _which_bool("codex") || os.is_dir(codex_home) {
		found_any = true
		fmt.println("  Codex")
		if dir := _mcp_try("Codex", codex_home); dir != "" {
			defer delete(dir)
			_mcp_codex(dir, mcp_bin)
		}
		fmt.println()
	}

	// ── OpenCode ─────────────────────────────────────────────────────────
	oc_home := _opencode_cfg_dir(home)
	if _which_bool("opencode") || os.is_dir(oc_home) {
		found_any = true
		fmt.println("  OpenCode")
		if dir := _mcp_try("OpenCode", oc_home); dir != "" {
			defer delete(dir)
			_mcp_opencode(dir, mcp_bin)
		}
		fmt.println()
	}

	// ── Antigravity ──────────────────────────────────────────────────────
	gemini_home := _pjoin(home, ".gemini")
	if os.is_dir(gemini_home) {
		found_any = true
		fmt.println("  Antigravity")
		_mcp_antigravity(_pjoin(gemini_home, "antigravity"), mcp_bin)
		fmt.println()
	}

	// ── Hermes Agent ─────────────────────────────────────────────────────
	hermes_home := _hermes_cfg_dir(home)
	if _which_bool("hermes") || os.is_dir(hermes_home) {
		found_any = true
		fmt.println("  Hermes Agent")
		if dir := _mcp_try("Hermes", hermes_home); dir != "" {
			defer delete(dir)
			_mcp_hermes(dir, mcp_bin)
		}
		fmt.println()
	}

	if !found_any {
		fmt.println("  No AI coding tools detected.")
		fmt.println("  When installed, register olt-mcp using the snippets below.")
		_print_all_mcp_snippets(home, mcp_bin)
	}
}

// ── Claude Code ───────────────────────────────────────────────────────────────

@(private = "file")
_mcp_claude :: proc(mcp_bin: string) {
	fmt.print("    Register via 'claude mcp add'? [Y/n]: ")
	if _yn_default_yes() {
		state, _, _, err := os.process_exec(
			os.Process_Desc{command = []string{"claude", "mcp", "add", "olt-mcp", mcp_bin}},
			context.allocator,
		)
		if err != nil || !state.success {
			fmt.println("    ✗  'claude mcp add' failed. Add manually to ~/.claude.json or .mcp.json:")
			_snippet_mcpservers(mcp_bin)
		} else {
			fmt.println("    ✓  olt-mcp registered")
		}
	} else {
		fmt.println("    Skipped. Add to ~/.claude.json or project .mcp.json:")
		_snippet_mcpservers(mcp_bin)
	}
}

// ── Cursor ────────────────────────────────────────────────────────────────────
// Config: {cursor_dir}/mcp.json  (JSON, mcpServers key)

@(private = "file")
_mcp_cursor :: proc(cursor_dir, mcp_bin: string) {
	cfg_path := _pjoin(cursor_dir, "mcp.json")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.println("    Config exists — add under \"mcpServers\":")
		_snippet_mcpservers_entry(mcp_bin)
		return
	}
	fmt.printf("    Create %s? [Y/n]: ", cfg_path)
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create it with:")
		_snippet_mcpservers(mcp_bin)
		return
	}
	content := _snippet_mcpservers_str(mcp_bin)
	defer delete(content)
	if err := os.write_entire_file(cfg_path, transmute([]u8)content); err != nil {
		fmt.printfln("    ✗  Write failed. Create %s with:", cfg_path)
		_snippet_mcpservers(mcp_bin)
	} else {
		fmt.printfln("    ✓  Created %s", cfg_path)
	}
}

// ── Cline ─────────────────────────────────────────────────────────────────────
// Config: {settings_dir}/cline_mcp_settings.json  (JSON, mcpServers key)
// macOS:  ~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/
// Linux:  ~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/
// Windows:%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\

@(private = "file")
_mcp_cline :: proc(settings_dir, mcp_bin: string) {
	cfg_path := _pjoin(settings_dir, "cline_mcp_settings.json")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.println("    Config exists — add under \"mcpServers\":")
		_snippet_mcpservers_entry(mcp_bin)
		return
	}
	fmt.printf("    Create %s? [Y/n]: ", cfg_path)
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create it with:")
		_snippet_mcpservers(mcp_bin)
		return
	}
	if !os.is_dir(settings_dir) { _mkdir_p(settings_dir) }
	content := _snippet_mcpservers_str(mcp_bin)
	defer delete(content)
	if err := os.write_entire_file(cfg_path, transmute([]u8)content); err != nil {
		fmt.printfln("    ✗  Write failed. Create %s with:", cfg_path)
		_snippet_mcpservers(mcp_bin)
	} else {
		fmt.printfln("    ✓  Created %s", cfg_path)
	}
}

// ── Codex ─────────────────────────────────────────────────────────────────────
// Config: {codex_dir}/config.toml  (TOML, [mcp_servers.olt_mcp] section)

@(private = "file")
_mcp_codex :: proc(codex_dir, mcp_bin: string) {
	cfg_path := _pjoin(codex_dir, "config.toml")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.print("    Append olt-mcp section to config.toml? [Y/n]: ")
		if !_yn_default_yes() {
			fmt.println("    Skipped. Add to config.toml:")
			_snippet_codex(mcp_bin)
			return
		}
		section := _snippet_codex_str(mcp_bin)
		defer delete(section)
		b := strings.builder_make(allocator = context.temp_allocator)
		strings.write_bytes(&b, existing)
		strings.write_string(&b, "\n")
		strings.write_string(&b, section)
		if err2 := os.write_entire_file(cfg_path, transmute([]u8)strings.to_string(b)); err2 != nil {
			fmt.println("    ✗  Write failed. Add manually:")
			_snippet_codex(mcp_bin)
		} else {
			fmt.println("    ✓  Appended to config.toml")
		}
		return
	}
	fmt.print("    Create config.toml with olt-mcp entry? [Y/n]: ")
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create config.toml with:")
		_snippet_codex(mcp_bin)
		return
	}
	if !os.is_dir(codex_dir) { _mkdir_p(codex_dir) }
	section := _snippet_codex_str(mcp_bin)
	defer delete(section)
	if err := os.write_entire_file(cfg_path, transmute([]u8)section); err != nil {
		fmt.println("    ✗  Write failed. Create config.toml with:")
		_snippet_codex(mcp_bin)
	} else {
		fmt.println("    ✓  Created config.toml")
	}
}

// ── OpenCode ──────────────────────────────────────────────────────────────────
// Config: {opencode_dir}/opencode.json  (JSON, "mcp" key, type:"local")

@(private = "file")
_mcp_opencode :: proc(opencode_dir, mcp_bin: string) {
	cfg_path := _pjoin(opencode_dir, "opencode.json")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.println("    Config exists — add under the \"mcp\" key:")
		_snippet_opencode_entry(mcp_bin)
		return
	}
	fmt.print("    Create opencode.json with olt-mcp entry? [Y/n]: ")
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create opencode.json with:")
		_snippet_opencode_full(mcp_bin)
		return
	}
	if !os.is_dir(opencode_dir) { _mkdir_p(opencode_dir) }
	content := _snippet_opencode_full_str(mcp_bin)
	defer delete(content)
	if err := os.write_entire_file(cfg_path, transmute([]u8)content); err != nil {
		fmt.println("    ✗  Write failed. Create opencode.json with:")
		_snippet_opencode_full(mcp_bin)
	} else {
		fmt.println("    ✓  Created opencode.json")
	}
}

// ── Antigravity ───────────────────────────────────────────────────────────────
// Config: {ag_dir}/mcp_config.json  (JSON, mcpServers key)

@(private = "file")
_mcp_antigravity :: proc(ag_dir, mcp_bin: string) {
	cfg_path := _pjoin(ag_dir, "mcp_config.json")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.println("    Config exists — add under \"mcpServers\":")
		_snippet_mcpservers_entry(mcp_bin)
		return
	}
	fmt.printf("    Create %s? [Y/n]: ", cfg_path)
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create it with:")
		_snippet_mcpservers(mcp_bin)
		return
	}
	if !os.is_dir(ag_dir) { _mkdir_p(ag_dir) }
	content := _snippet_mcpservers_str(mcp_bin)
	defer delete(content)
	if err := os.write_entire_file(cfg_path, transmute([]u8)content); err != nil {
		fmt.printfln("    ✗  Write failed. Create %s with:", cfg_path)
		_snippet_mcpservers(mcp_bin)
	} else {
		fmt.printfln("    ✓  Created %s", cfg_path)
	}
}

// ── Hermes Agent ──────────────────────────────────────────────────────────────
// Config: {hermes_dir}/config.yaml  (YAML, mcp_servers key)
// macOS/Linux: ~/.hermes/config.yaml
// Windows:     %LOCALAPPDATA%\hermes\config.yaml

@(private = "file")
_mcp_hermes :: proc(hermes_dir, mcp_bin: string) {
	cfg_path := _pjoin(hermes_dir, "config.yaml")
	if os.is_file(cfg_path) {
		existing, err := os.read_entire_file_from_path(cfg_path, context.temp_allocator)
		if err == nil && strings.contains(string(existing), "olt") {
			fmt.println("    Already configured ✓")
			return
		}
		fmt.println("    Config exists — add under mcp_servers:")
		_snippet_hermes_entry(mcp_bin)
		return
	}
	fmt.printf("    Create %s? [Y/n]: ", cfg_path)
	if !_yn_default_yes() {
		fmt.println("    Skipped. Create it with:")
		_snippet_hermes_full(mcp_bin)
		return
	}
	if !os.is_dir(hermes_dir) { _mkdir_p(hermes_dir) }
	content := _snippet_hermes_full_str(mcp_bin)
	defer delete(content)
	if err := os.write_entire_file(cfg_path, transmute([]u8)content); err != nil {
		fmt.printfln("    ✗  Write failed. Create %s with:", cfg_path)
		_snippet_hermes_full(mcp_bin)
	} else {
		fmt.printfln("    ✓  Created %s", cfg_path)
	}
}

// =============================================================================
// Config snippets
// =============================================================================

// _snippet_mcpservers prints a complete JSON file with the mcpServers root key.
// Used by: Claude Code, Cursor, Cline, Antigravity (all share this format).
@(private = "file")
_snippet_mcpservers :: proc(mcp_bin: string) {
	fmt.println(`    {`)
	fmt.println(`      "mcpServers": {`)
	fmt.println(`        "olt-mcp": {`)
	fmt.printfln(`          "command": "%s",`, mcp_bin)
	fmt.println(`          "args": []`)
	fmt.println(`        }`)
	fmt.println(`      }`)
	fmt.println(`    }`)
}

// _snippet_mcpservers_entry prints just the inner "olt-mcp" entry for manual insertion.
@(private = "file")
_snippet_mcpservers_entry :: proc(mcp_bin: string) {
	fmt.println(`    "olt-mcp": {`)
	fmt.printfln(`      "command": "%s",`, mcp_bin)
	fmt.println(`      "args": []`)
	fmt.println(`    }`)
}

@(private = "file")
_snippet_mcpservers_str :: proc(mcp_bin: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	fmt.sbprintf(&b,
		"{\n  \"mcpServers\": {\n    \"olt-mcp\": {\n      \"command\": \"%s\",\n      \"args\": []\n    }\n  }\n}\n",
		mcp_bin)
	return strings.clone(strings.to_string(b))
}

@(private = "file")
_snippet_codex :: proc(mcp_bin: string) {
	fmt.println(`    [mcp_servers.olt_mcp]`)
	fmt.printfln(`    command = "%s"`, mcp_bin)
	fmt.println(`    enabled = true`)
}

@(private = "file")
_snippet_codex_str :: proc(mcp_bin: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	fmt.sbprintf(&b, "[mcp_servers.olt_mcp]\ncommand = \"%s\"\nenabled = true\n", mcp_bin)
	return strings.clone(strings.to_string(b))
}

@(private = "file")
_snippet_opencode_entry :: proc(mcp_bin: string) {
	fmt.println(`    "olt-mcp": {`)
	fmt.println(`      "type": "local",`)
	fmt.printfln(`      "command": ["%s"]`, mcp_bin)
	fmt.println(`    }`)
}

@(private = "file")
_snippet_opencode_full :: proc(mcp_bin: string) {
	fmt.println(`    {`)
	fmt.println(`      "mcp": {`)
	fmt.println(`        "olt-mcp": {`)
	fmt.println(`          "type": "local",`)
	fmt.printfln(`          "command": ["%s"]`, mcp_bin)
	fmt.println(`        }`)
	fmt.println(`      }`)
	fmt.println(`    }`)
}

@(private = "file")
_snippet_opencode_full_str :: proc(mcp_bin: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	fmt.sbprintf(&b,
		"{\n  \"mcp\": {\n    \"olt-mcp\": {\n      \"type\": \"local\",\n      \"command\": [\"%s\"]\n    }\n  }\n}\n",
		mcp_bin)
	return strings.clone(strings.to_string(b))
}

@(private = "file")
_snippet_hermes_entry :: proc(mcp_bin: string) {
	fmt.println(`      olt-mcp:`)
	fmt.printfln(`        command: %s`, mcp_bin)
	fmt.println(`        args: []`)
}

@(private = "file")
_snippet_hermes_full :: proc(mcp_bin: string) {
	fmt.println(`    mcp_servers:`)
	_snippet_hermes_entry(mcp_bin)
}

@(private = "file")
_snippet_hermes_full_str :: proc(mcp_bin: string) -> string {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	fmt.sbprintf(&b, "mcp_servers:\n  olt-mcp:\n    command: %s\n    args: []\n", mcp_bin)
	return strings.clone(strings.to_string(b))
}

// _print_all_mcp_snippets shows concise manual setup for all supported tools.
@(private = "file")
_print_all_mcp_snippets :: proc(home, mcp_bin: string) {
	fmt.println()
	fmt.println("  Claude Code / Cursor / Cline / Antigravity — JSON, mcpServers key:")
	fmt.println("    Files:")
	fmt.println("      Claude Code:  ~/.claude.json  or  .mcp.json")
	fmt.printfln("      Cursor:       %s", _pjoin(home, ".cursor", "mcp.json"))
	fmt.printfln("      Cline:        %s", _pjoin(_cline_settings_dir(home), "cline_mcp_settings.json"))
	fmt.printfln("      Antigravity:  %s", _pjoin(home, ".gemini", "antigravity", "mcp_config.json"))
	fmt.println("    Config:")
	_snippet_mcpservers(mcp_bin)
	fmt.println()
	fmt.println("  Codex — ~/.codex/config.toml:")
	_snippet_codex(mcp_bin)
	fmt.println()
	fmt.println("  OpenCode — ~/.config/opencode/opencode.json:")
	_snippet_opencode_full(mcp_bin)
	fmt.println()
	fmt.println("  Hermes Agent — ~/.hermes/config.yaml:")
	_snippet_hermes_full(mcp_bin)
}
