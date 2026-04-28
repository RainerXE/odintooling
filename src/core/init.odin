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
	_init_header(1, 2, "OLS (Odin Language Server)")
	_init_ols_step()
	fmt.println()

	// ── Step 2: Install ──────────────────────────────────────────────────────
	_init_header(2, 2, "Install")
	_install_step()
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
	state, stdout, _, err := os.process_exec(
		os.Process_Desc{command = []string{"which", name}},
		context.allocator,
	)
	defer delete(stdout)
	if err != nil || !state.success { return "" }
	return strings.clone(strings.trim(string(stdout), " \t\r\n"))
}

@(private = "file")
_own_bin_dir :: proc() -> string {
	if len(os.args) == 0 { return "." }
	arg0 := os.args[0]
	if !strings.contains(arg0, "/") {
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
