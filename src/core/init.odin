package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// olt --init    — interactive first-run setup wizard
// olt --install — create symlinks in ~/.local/bin/
// =============================================================================
//
// --init  walks the user through:
//   1. Locating / configuring OLS (Odin Language Server)
//   2. Creating an olt.toml with a chosen rule profile
//   3. Installing binaries to ~/.local/bin/
//
// --install runs only step 3 (useful after a rebuild).
// =============================================================================

// run_init_command runs the interactive first-run wizard. Returns exit code.
run_init_command :: proc() -> int {
	fmt.printfln("olt %s  —  First-run setup", OLT_VERSION)
	fmt.println()

	// ── Step 1: OLS ──────────────────────────────────────────────────────────
	_init_header(1, 3, "OLS (Odin Language Server)")
	ols_path := _init_ols_step()
	fmt.println()

	// ── Step 2: Config ───────────────────────────────────────────────────────
	_init_header(2, 3, "Project configuration")
	_init_config_step(ols_path)
	fmt.println()

	// ── Step 3: Install ──────────────────────────────────────────────────────
	_init_header(3, 3, "Install")
	_install_step()
	fmt.println()

	fmt.println("Setup complete.  Run 'olt --help' to get started.")
	return 0
}

// run_install_command runs only the install step. Returns exit code.
run_install_command :: proc() -> int {
	fmt.printfln("olt %s  —  Install", OLT_VERSION)
	fmt.println()
	_install_step()
	return 0
}

// =============================================================================
// Step implementations
// =============================================================================

@(private = "file")
_init_ols_step :: proc() -> (ols_path: string) {
	found := _which("ols")
	if found != "" {
		fmt.printfln("  Found ols: %s", found)
		fmt.print("  Use a different path? [y/N]: ")
		if _yn_default_no() {
			fmt.print("  Path: ")
			return _readline()
		}
		return found
	}

	fmt.println("  OLS not found in PATH.")
	fmt.println("  OLS provides type-checking and completions in your editor.")
	fmt.println("  Get it from: https://github.com/DanielGavin/ols")
	fmt.println()
	fmt.print("  Enter path to ols binary, or leave blank to skip: ")
	entered := _readline()
	if entered != "" && os.is_file(entered) {
		fmt.printfln("  Will write ols_path = \"%s\" to olt.toml.", entered)
		return entered
	}
	if entered != "" {
		fmt.printfln("  Warning: %s does not exist — skipping ols_path.", entered)
	} else {
		fmt.println("  Skipped — configure ols_path in olt.toml later if needed.")
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

	bin_dir  := _own_bin_dir()
	dst_dir  := strings.join([]string{home, ".local", "bin"}, "/")
	defer delete(dst_dir)

	fmt.printfln("  Source:  %s/", bin_dir)
	fmt.printfln("  Target:  %s/", dst_dir)
	fmt.println()
	fmt.print("  Install olt, olt-mcp, olt-lsp? [Y/n]: ")
	if !_yn_default_yes() {
		fmt.println("  Skipped.")
		return
	}

	// Create target directory if needed.
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

	// Resolve bin_dir to an absolute path so symlinks work from any directory.
	abs_bin_dir := _resolve_path(bin_dir)
	defer delete(abs_bin_dir)

	bins := [?]string{"olt", "olt-mcp", "olt-lsp"}
	for name in bins {
		src := strings.join([]string{abs_bin_dir, name}, "/")
		defer delete(src)
		dst := strings.join([]string{dst_dir, name}, "/")
		defer delete(dst)

		if !os.is_file(src) {
			fmt.printfln("  -  %s not found at %s — skipping", name, src)
			continue
		}
		// Remove existing entry (ignore error — may not exist yet).
		_ = os.remove(dst)
		state, _, _, err := os.process_exec(
			os.Process_Desc{command = []string{"ln", "-sf", src, dst}},
			context.allocator,
		)
		if err != nil || !state.success {
			fmt.printfln("  ✗  %s", name)
		} else {
			fmt.printfln("  ✓  %s", name)
		}
	}

	// Report PATH status.
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

// =============================================================================
// Helpers
// =============================================================================

@(private = "file")
_init_header :: proc(step, total: int, name: string) {
	fmt.printfln("--- %d/%d  %s", step, total, name)
	fmt.println()
}

// _readline reads a trimmed line from stdin and returns a heap-allocated copy.
// Caller owns the returned string (or it may be leaked safely on process exit).
@(private = "file")
_readline :: proc() -> string {
	buf: [512]u8
	n, _ := os.read(os.stdin, buf[:])
	if n <= 0 { return "" }
	trimmed := strings.trim(string(buf[:n]), " \t\r\n")
	return strings.clone(trimmed)  // clone before buf goes out of scope
}

// _yn_default_yes reads Y/n — returns true unless user types "n" or "no".
@(private = "file")
_yn_default_yes :: proc() -> bool {
	ans := _readline()
	defer delete(ans)
	return !strings.equal_fold(ans, "n") && !strings.equal_fold(ans, "no")
}

// _yn_default_no reads y/N — returns true only if user types "y" or "yes".
@(private = "file")
_yn_default_no :: proc() -> bool {
	ans := _readline()
	defer delete(ans)
	return strings.equal_fold(ans, "y") || strings.equal_fold(ans, "yes")
}

// _which runs `which <name>` and returns a heap-allocated path, or "" if not found.
@(private = "file")
_which :: proc(name: string) -> string {
	state, stdout, _, err := os.process_exec(
		os.Process_Desc{command = []string{"which", name}},
		context.allocator,
	)
	defer delete(stdout)
	if err != nil || !state.success { return "" }
	// Clone before stdout is freed by defer.
	return strings.clone(strings.trim(string(stdout), " \t\r\n"))
}

// _own_bin_dir returns the directory that contains the running olt binary.
@(private = "file")
_own_bin_dir :: proc() -> string {
	if len(os.args) == 0 { return "." }
	arg0 := os.args[0]
	if !strings.contains(arg0, "/") {
		// Invoked by name from PATH — look for ./artifacts/ first.
		if os.is_dir("artifacts") { return "artifacts" }
		return "."
	}
	return filepath_dir(arg0)
}

// _resolve_path turns a relative path into an absolute one by prepending CWD.
@(private = "file")
_resolve_path :: proc(p: string) -> string {
	if strings.has_prefix(p, "/") { return strings.clone(p) }
	// Shell out to pwd for CWD — Odin has no os.getcwd on all platforms.
	state, stdout, _, err := os.process_exec(
		os.Process_Desc{command = []string{"pwd"}},
		context.allocator,
	)
	defer delete(stdout)
	if err != nil || !state.success { return strings.clone(p) }
	cwd := strings.trim(string(stdout), " \t\r\n")
	// Strip leading "./" from p if present.
	rel := p
	if strings.has_prefix(rel, "./") { rel = rel[2:] }
	return strings.join([]string{cwd, rel}, "/")
}

// _build_toml generates olt.toml content for the chosen profile.
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
