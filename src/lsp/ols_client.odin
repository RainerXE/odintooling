package lsp_proxy

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

// =============================================================================
// OLSProcess — vanilla OLS subprocess with bidirectional pipes
// =============================================================================
//
// The proxy spawns OLS once and keeps it alive for the editor session.
// Thread A writes requests to stdin_w; Thread B reads responses from stdout_r.
//
//   stdin_w   ──write──► [OLS stdin pipe read-end]
//   stdout_r  ◄──read──  [OLS stdout pipe write-end]
//
// =============================================================================

OLSProcess :: struct {
	process:  os.Process,
	stdin_w:  ^os.File, // write to OLS's stdin
	stdout_r: ^os.File, // read from OLS's stdout
	started:  bool,
}

// ols_start spawns OLS at ols_path and returns an OLSProcess with live pipes.
// The caller owns the returned process and must call ols_stop when done.
ols_start :: proc(ols_path: string) -> (proc_: OLSProcess, ok: bool) {
	// Pipe for OLS stdin:  we write stdin_w → OLS reads stdin_r
	stdin_r, stdin_w, err1 := os.pipe()
	if err1 != nil {
		fmt.eprintfln("odin-lint-lsp: os.pipe() for OLS stdin failed: %v", err1)
		return
	}

	// Pipe for OLS stdout: OLS writes stdout_w → we read stdout_r
	stdout_r, stdout_w, err2 := os.pipe()
	if err2 != nil {
		fmt.eprintfln("odin-lint-lsp: os.pipe() for OLS stdout failed: %v", err2)
		os.close(stdin_r) // odin-lint:ignore C201
		os.close(stdin_w) // odin-lint:ignore C201
		return
	}

	desc := os.Process_Desc{
		command = []string{ols_path},
		stdin   = stdin_r,
		stdout  = stdout_w,
		stderr  = stdout_w, // merge stderr into stdout stream
	}

	p, perr := os.process_start(desc)
	if perr != nil {
		fmt.eprintfln("odin-lint-lsp: failed to start OLS at '%s': %v", ols_path, perr)
		os.close(stdin_r)  // odin-lint:ignore C201
		os.close(stdin_w)  // odin-lint:ignore C201
		os.close(stdout_r) // odin-lint:ignore C201
		os.close(stdout_w) // odin-lint:ignore C201
		return
	}

	// Close the ends we don't use in this process.
	os.close(stdin_r)  // odin-lint:ignore C201  OLS owns the read-end of its stdin
	os.close(stdout_w) // odin-lint:ignore C201  OLS owns the write-end of its stdout

	proc_ = OLSProcess{
		process  = p,
		stdin_w  = stdin_w,
		stdout_r = stdout_r,
		started  = true,
	}
	ok = true
	return
}

// ols_write sends bytes to OLS's stdin with LSP Content-Length framing.
ols_write :: proc(p: ^OLSProcess, bytes: []u8) -> bool {
	if !p.started { return false }
	header := fmt.tprintf("Content-Length: %d\r\n\r\n", len(bytes))
	w := os.to_writer(p.stdin_w)
	_, e1 := io.write_string(w, header)
	_, e2 := io.write(w, bytes)
	return e1 == nil && e2 == nil
}

// ols_make_reader returns a bufio.Reader backed by the OLS stdout pipe.
// The caller must provide a backing buffer slice (e.g. make([]u8, 64*1024)).
ols_make_reader :: proc(p: ^OLSProcess, buf: []u8) -> bufio.Reader {
	r: bufio.Reader
	bufio.reader_init_with_buf(&r, os.to_reader(p.stdout_r), buf)
	return r
}

// ols_stop sends the LSP exit notification, then terminates the process.
ols_stop :: proc(p: ^OLSProcess) {
	if !p.started { return }
	exit_notif := `{"jsonrpc":"2.0","method":"exit"}`
	ols_write(p, transmute([]u8)string(exit_notif))
	_ = os.process_kill(p.process)
	os.close(p.stdin_w)  // odin-lint:ignore C201
	os.close(p.stdout_r) // odin-lint:ignore C201
	p.started = false
}
