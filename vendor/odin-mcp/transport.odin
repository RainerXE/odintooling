/*
	odin-mcp — Reusable MCP Protocol Library
	File: vendor/odin-mcp/transport.odin

	Content-Length framing for the MCP stdio transport.
	Identical framing to LSP: each message is preceded by
	"Content-Length: N\r\n\r\n" followed by N UTF-8 bytes of JSON.
*/
package mcp

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

// read_message reads one framed MCP message from reader.
// Returns the raw JSON bytes on success (allocated with allocator).
// Returns ok=false on EOF or a malformed frame — the caller should exit cleanly.
read_message :: proc(reader: ^bufio.Reader, allocator: runtime.Allocator) -> (json_bytes: []u8, ok: bool) {
	content_length := -1

	// Read header lines until the blank line.
	for {
		line, err := bufio.reader_read_string(reader, '\n', context.temp_allocator)
		if err != nil {
			return nil, false // EOF or I/O error
		}
		// Trim trailing \r\n or \n
		line = strings.trim_right(line, "\r\n")
		if line == "" {
			break // blank line — end of headers
		}
		if strings.has_prefix(line, "Content-Length:") {
			val := strings.trim_space(line[len("Content-Length:"):])
			n, parse_ok := strconv.parse_int(val)
			if !parse_ok || n < 0 {
				return nil, false
			}
			content_length = n
		}
		// Other headers (Content-Type etc.) are ignored.
	}

	if content_length < 0 {
		return nil, false // no Content-Length header found
	}
	if content_length == 0 {
		return []u8{}, true
	}

	// Read exactly content_length bytes.
	buf := make([]u8, content_length, allocator)
	total := 0
	for total < content_length {
		n, err := bufio.reader_read(reader, buf[total:])
		total += n
		if err != nil && total < content_length {
			return nil, false
		}
	}
	return buf, true
}

// write_message writes one framed MCP message to stdout.
// json_bytes must be the complete JSON payload.
write_message :: proc(json_bytes: []u8) -> bool {
	header := fmt.tprintf("Content-Length: %d\r\n\r\n", len(json_bytes))
	w := os.to_writer(os.stdout)
	_, err1 := io.write_string(w, header)
	_, err2 := io.write(w, json_bytes)
	return err1 == nil && err2 == nil
}

// write_string_message is a convenience wrapper for string payloads.
write_string_message :: proc(s: string) -> bool {
	return write_message(transmute([]u8)s)
}
