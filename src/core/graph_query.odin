// graph_query.odin — `olt symbol|callers|refs`: query the code graph from the CLI.
//
// These commands read the same tables as the MCP graph tools and print the same
// JSON payloads (see src/mcp/tool_graph.odin), so a consumer can switch transports
// without changing its parser. `olt --list-kinds` documents the node kinds.
package core

import "core:fmt"
import "core:os"
import "core:strings"

GraphQueryOptions :: struct {
	name:    string,
	json:    bool,
	db_path: string,
	help:    bool,
}

// run_graph_query_command answers `olt symbol|callers|refs`. Exit codes: 0 answer
// printed, 1 symbol not found, 2 usage/ambiguity/database error.
run_graph_query_command :: proc(command: string, args: []string) -> int {
	opts, parse_ok := _gq_parse_args(args)
	if !parse_ok { return 2 }
	if opts.help {
		_gq_print_help(command)
		return 0
	}
	if opts.name == "" {
		fmt.eprintfln("error: olt %s requires a symbol name", command)
		fmt.eprintfln("usage: olt %s <name> [--json] [--db <path>]", command)
		return 2
	}

	db_path := opts.db_path
	if db_path == "" { db_path = GRAPH_DB_PATH }

	db, opened := graph_open_existing(db_path)
	if !opened {
		if os.is_file(db_path) {
			fmt.eprintfln("error: %s needs a rebuild (older schema or analysis); run 'olt <target> --export-symbols'", db_path)
		} else {
			fmt.eprintfln("error: graph db not found at %s; run 'olt <target> --export-symbols' first", db_path)
		}
		return 2
	}
	defer graph_close(db)

	if changed, stale := graph_stale_file(db); stale {
		defer delete(changed)
		fmt.eprintfln("note: %s changed after the graph was built; re-run 'olt <target> --export-symbols' for current answers", changed)
	}

	// Resolve first: a plain name can be ambiguous across packages, and guessing
	// the first match would silently answer about the wrong declaration.
	candidates := graph_find_candidates(db, opts.name)
	defer graph_free_candidates(candidates)
	if len(candidates) == 0 {
		fmt.eprintfln("error: symbol '%s' not found in %s", opts.name, db_path)
		return 1
	}
	if len(candidates) > 1 {
		fmt.eprintfln("error: '%s' matches %d declarations; pass package::name:", opts.name, len(candidates))
		for c in candidates {
			fmt.eprintfln("  %s  (%s)  %s:%d", c.qualified_name, c.kind, c.file, c.line)
		}
		return 2
	}

	switch command {
	case "symbol":  return _gq_symbol(db, opts)
	case "callers": return _gq_callers(db, opts)
	case "refs":    return _gq_refs(db, opts)
	}
	fmt.eprintfln("error: unknown graph query '%s'", command)
	return 2
}

// print_list_kinds documents the node kinds the exporter writes. Queries match
// these values exactly; procedures are `function`, not `proc`.
print_list_kinds :: proc() {
	fmt.println("file\tone indexed source file")
	fmt.println("function\tprocedures (Odin proc), procedure groups, generic instantiations")
	fmt.println("struct\tstruct and bit_field types")
	fmt.println("union\tunion types")
	fmt.println("enum\tenum types")
	fmt.println("enum_member\tone member of an enum")
	fmt.println("constant\tconstants")
	fmt.println("variable\tpackage-level variables")
	fmt.println("import\tan import declaration (the imported path)")
}

@(private)
_gq_symbol :: proc(db: ^GraphDB, opts: GraphQueryOptions) -> int {
	node, found := graph_get_node(db, opts.name)
	if !found {
		fmt.eprintfln("error: symbol '%s' not found in %s", opts.name, db.path)
		return 1
	}
	defer graph_free_node_info(node)

	role := node.memory_role
	if role == "" { role = "neutral" }
	violations := node.lint_violations
	if violations == "" { violations = "[]" }

	if opts.json {
		b := strings.builder_make()
		defer strings.builder_destroy(&b)
		strings.write_string(&b, `{"name":`)
		_gq_json_string(&b, node.name)
		strings.write_string(&b, `,"kind":`)
		_gq_json_string(&b, node.kind)
		strings.write_string(&b, `,"file":`)
		_gq_json_string(&b, node.file)
		fmt.sbprintf(&b, `,"line":%d,"signature":`, node.line)
		_gq_json_string(&b, node.signature)
		strings.write_string(&b, `,"memory_role":`)
		_gq_json_string(&b, role)
		fmt.sbprintf(&b, `,"lint_violations":%s}`, violations)
		fmt.println(strings.to_string(b))
		return 0
	}

	fmt.printf("%s  (%s)\n", node.name, node.kind)
	fmt.printf("  file:      %s:%d\n", node.file, node.line)
	if node.signature != "" {
		fmt.printf("  signature: %s\n", node.signature)
	}
	fmt.printf("  memory:    %s\n", role)
	lint_text := _gq_lint_text(violations)
	if lint_text != "" {
		fmt.printf("  lint:      %s\n", lint_text)
	}
	return 0
}

@(private)
_gq_callers :: proc(db: ^GraphDB, opts: GraphQueryOptions) -> int {
	node, found := graph_get_node(db, opts.name)
	if !found {
		fmt.eprintfln("error: symbol '%s' not found in %s", opts.name, db.path)
		return 1
	}
	defer graph_free_node_info(node)

	callers := graph_get_callers(db, node.id)
	defer {
		for c in callers { graph_free_node_info(c) }
		delete(callers)
	}

	if opts.json {
		b := strings.builder_make()
		defer strings.builder_destroy(&b)
		strings.write_string(&b, `{"proc":`)
		_gq_json_string(&b, node.name)
		fmt.sbprintf(&b, `,"caller_count":%d,"callers":[`, len(callers))
		for c, i in callers {
			if i > 0 { strings.write_byte(&b, ',') }
			strings.write_string(&b, `{"name":`)
			_gq_json_string(&b, c.name)
			strings.write_string(&b, `,"file":`)
			_gq_json_string(&b, c.file)
			fmt.sbprintf(&b, `,"line":%d}`, c.line)
		}
		strings.write_string(&b, "]}")
		fmt.println(strings.to_string(b))
		return 0
	}

	if len(callers) == 0 {
		fmt.printf("%s has no callers in the graph.\n", node.name)
		return 0
	}
	fmt.printf("%s is called by %d procedure(s):\n", node.name, len(callers))
	for c in callers {
		fmt.printf("  %s  %s:%d\n", c.name, c.file, c.line)
	}
	return 0
}

@(private)
_gq_refs :: proc(db: ^GraphDB, opts: GraphQueryOptions) -> int {
	node, found := graph_get_node(db, opts.name)
	if !found {
		fmt.eprintfln("error: symbol '%s' not found in %s", opts.name, db.path)
		return 1
	}
	defer graph_free_node_info(node)

	refs := graph_get_references(db, node.id)
	defer {
		for r in refs {
			delete(r.source_name); delete(r.target_name); delete(r.kind); delete(r.file)
		}
		delete(refs)
	}

	if opts.json {
		b := strings.builder_make()
		defer strings.builder_destroy(&b)
		strings.write_string(&b, `{"symbol":`)
		_gq_json_string(&b, node.name)
		fmt.sbprintf(&b, `,"reference_count":%d,"references":[`, len(refs))
		for r, i in refs {
			if i > 0 { strings.write_byte(&b, ',') }
			strings.write_string(&b, `{"caller":`)
			_gq_json_string(&b, r.source_name)
			strings.write_string(&b, `,"file":`)
			_gq_json_string(&b, r.file)
			fmt.sbprintf(&b, `,"line":%d,"kind":`, r.line)
			_gq_json_string(&b, r.kind)
			strings.write_byte(&b, '}')
		}
		strings.write_string(&b, "]}")
		fmt.println(strings.to_string(b))
		return 0
	}

	if len(refs) == 0 {
		fmt.printf("%s has no references in the graph.\n", node.name)
		return 0
	}
	fmt.printf("%d reference(s) to %s:\n", len(refs), node.name)
	for r in refs {
		fmt.printf("  %s  %s:%d  %s\n", r.source_name, r.file, r.line, r.kind)
	}
	return 0
}

@(private)
_gq_parse_args :: proc(args: []string) -> (opts: GraphQueryOptions, ok: bool) {
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--json":
			opts.json = true
		case arg == "--help" || arg == "-h":
			opts.help = true
		case strings.has_prefix(arg, "--db="):
			opts.db_path = arg[len("--db="):]
		case arg == "--db":
			if i + 1 >= len(args) {
				fmt.eprintln("error: --db requires a path")
				return opts, false
			}
			i += 1
			opts.db_path = args[i]
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("error: unknown flag '%s'", arg)
			return opts, false
		case:
			if opts.name != "" {
				fmt.eprintfln("error: unexpected argument '%s'", arg)
				return opts, false
			}
			opts.name = arg
		}
		i += 1
	}
	return opts, true
}

@(private)
_gq_print_help :: proc(command: string) {
	description := "Look up a declaration in the code graph."
	switch command {
	case "callers": description = "List the procedures that call a declaration."
	case "refs":    description = "List reference sites for a declaration."
	}
	fmt.printf("Usage: olt %s <name> [--json] [--db <path>]\n\n", command)
	fmt.printf("%s\n\n", description)
	fmt.println("A plain name must be unique; when two packages define the same name, pass")
	fmt.println("the qualified form package::name. Node kinds: olt --list-kinds.")
	fmt.println()
	fmt.println("  --json        Print one JSON object (the MCP payload shape)")
	fmt.println("  --db <path>   Graph database (default: .codegraph/olt.db)")
	fmt.println("  --help        Show this help")
}

// _gq_json_string writes s as a quoted JSON string. No allocation: the caller
// owns the builder.
@(private)
_gq_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for ch in s {
		switch ch {
		case '"':  strings.write_string(b, `\"`)
		case '\\': strings.write_string(b, `\\`)
		case '\n': strings.write_string(b, `\n`)
		case '\r': strings.write_string(b, `\r`)
		case '\t': strings.write_string(b, `\t`)
		case:
			if ch < 0x20 {
				fmt.sbprintf(b, `\u%04x`, u16(ch))
			} else {
				strings.write_rune(b, ch)
			}
		}
	}
	strings.write_byte(b, '"')
}

// _gq_lint_text renders the stored JSON array as "C001, C002" for text output.
@(private)
_gq_lint_text :: proc(violations: string) -> string {
	if violations == "" || violations == "[]" { return "" }
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	for ch in violations {
		if ch == '[' || ch == ']' || ch == '"' { continue }
		if ch == ',' {
			strings.write_string(&b, ", ")
			continue
		}
		strings.write_rune(&b, ch)
	}
	return strings.clone(strings.to_string(b))
}
