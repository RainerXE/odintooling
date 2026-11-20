// floorplan.odin — `olt floorplan`: turn the exported code graph into one
// self-contained HTML map. Read-only: it never changes the graph or the source.
package core

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import sq "../../vendor/odin-sqlite3"

FLOORPLAN_DEFAULT_OUT :: ".codegraph/floorplan.html"
FLOORPLAN_SCHEMA_VERSION :: 1

// Embedded assets live in ffi/floorplan/ so the binary has no runtime files.
FLOORPLAN_HTML :: #load("../../ffi/floorplan/index.html", string)
FLOORPLAN_CSS  :: #load("../../ffi/floorplan/app.css", string)
FLOORPLAN_JS   :: #load("../../ffi/floorplan/app.js", string)

FloorplanOptions :: struct {
	db_path:  string,
	out_path: string,
	title:    string,
	open:     bool,
	json:     bool,
	help:     bool,
}

// FloorplanResult is the shared result used by the CLI and the MCP tools.
// data_json is always populated; out_path/bytes are populated when write_html
// is true. stale_file is project-relative.
FloorplanResult :: struct {
	ok:         bool,
	not_found:  bool,
	error:      string,
	data_json:  string,
	out_path:   string,
	bytes:      int,
	files:      int,
	packages:   int,
	symbols:    int,
	edges:      int,
	unresolved: int,
	findings:   int,
	stale_file: string,
}

// floorplan_generate is the one implementation behind `olt floorplan` and the
// MCP tools. It reads an existing graph and never changes it or the source.
// db_path/out_path empty select the CLI defaults. write_html=false builds only
// the JSON data.
floorplan_generate :: proc(db_path, out_path, title: string, write_html: bool) -> FloorplanResult {
	result := FloorplanResult{}

	resolved, exists := _fp_resolve_db(db_path)
	if !exists {
		result.not_found = true
		if os.is_file(resolved) {
			result.error = fmt.tprintf("%s needs a rebuild (older schema or analysis); run 'olt <target> --export-symbols'", resolved)
		} else {
			result.error = fmt.tprintf("graph db not found at %s; run 'olt <target> --export-symbols' first", resolved)
		}
		return result
	}

	db, opened := graph_open_existing(resolved)
	if !opened {
		result.error = fmt.tprintf("could not open graph db at %s", resolved)
		return result
	}
	defer graph_close(db)

	stale_path, stale := graph_stale_file(db)
	defer if stale { delete(stale_path) }

	title_text := title
	if title_text == "" { title_text = _fp_project_name(db.root) }

	result.data_json  = _fp_build_data(db, resolved, title_text, stale_path if stale else "")
	result.files      = _fp_scalar_int(db, "SELECT COUNT(*) FROM files;")
	result.packages   = _fp_scalar_int(db, "SELECT COUNT(*) FROM (SELECT DISTINCT dir,name FROM odin_package);")
	result.symbols    = _fp_scalar_int(db, "SELECT COUNT(*) FROM nodes WHERE kind <> 'file';")
	result.edges      = _fp_scalar_int(db, "SELECT COUNT(*) FROM edges;")
	result.unresolved = _fp_scalar_int(db, "SELECT COUNT(*) FROM unresolved_refs;")
	result.findings   = _fp_finding_count(db)

	if write_html {
		out := out_path if out_path != "" else FLOORPLAN_DEFAULT_OUT
		html := _fp_render_html(result.data_json, title_text)
		if !_fp_mkdir_p(filepath_dir(out)) {
			result.error = fmt.tprintf("cannot create output directory for %s", out)
			return result
		}
		if err := os.write_entire_file(out, transmute([]u8)html); err != nil {
			result.error = fmt.tprintf("cannot write %s: %v", out, err)
			return result
		}
		result.out_path = out
		result.bytes    = len(html)
	}

	if stale { result.stale_file = graph_rel(db, stale_path) }
	result.ok = true
	return result
}

// run_floorplan_command implements `olt floorplan`. Exit codes: 0 success,
// 2 usage or database error.
run_floorplan_command :: proc(args: []string) -> int {
	opts, parse_ok := _fp_parse_args(args)
	if !parse_ok { return 2 }
	if opts.help {
		_fp_print_help()
		return 0
	}

	result := floorplan_generate(opts.db_path, opts.out_path, opts.title, !opts.json)
	if !result.ok {
		fmt.eprintfln("error: %s", result.error)
		return 2
	}
	if result.stale_file != "" {
		fmt.eprintfln("note: %s changed after the graph was built; the map may be stale", result.stale_file)
	}
	if opts.json {
		fmt.println(result.data_json)
		return 0
	}

	fmt.printfln("floorplan: wrote %s", result.out_path)
	fmt.printfln("  %d files · %d symbols · %d edges · %d findings",
		result.files, result.symbols, result.edges, result.findings)
	if opts.open { _fp_open_path(result.out_path) }
	return 0
}

// =============================================================================
// CLI
// =============================================================================

@(private)
_fp_parse_args :: proc(args: []string) -> (opts: FloorplanOptions, ok: bool) {
	ok = true
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--help" || arg == "-h":
			opts.help = true
		case arg == "--open":
			opts.open = true
		case arg == "--json":
			opts.json = true
		case arg == "--db":
			if i+1 >= len(args) {
				fmt.eprintln("error: --db requires a path")
				return opts, false
			}
			i += 1
			opts.db_path = args[i]
		case strings.has_prefix(arg, "--db="):
			opts.db_path = arg[len("--db="):]
			if opts.db_path == "" {
				fmt.eprintln("error: --db requires a path")
				return opts, false
			}
		case arg == "--out":
			if i+1 >= len(args) {
				fmt.eprintln("error: --out requires a path")
				return opts, false
			}
			i += 1
			opts.out_path = args[i]
		case strings.has_prefix(arg, "--out="):
			opts.out_path = arg[len("--out="):]
			if opts.out_path == "" {
				fmt.eprintln("error: --out requires a path")
				return opts, false
			}
		case arg == "--title":
			if i+1 >= len(args) {
				fmt.eprintln("error: --title requires text")
				return opts, false
			}
			i += 1
			opts.title = args[i]
		case strings.has_prefix(arg, "--title="):
			opts.title = arg[len("--title="):]
			if opts.title == "" {
				fmt.eprintln("error: --title requires text")
				return opts, false
			}
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("error: unknown flag '%s'", arg)
			return opts, false
		case:
			fmt.eprintfln("error: unexpected argument '%s' (olt floorplan takes no target)", arg)
			return opts, false
		}
		i += 1
	}
	return opts, true
}

@(private)
_fp_print_help :: proc() {
	fmt.println("Usage: olt floorplan [options]")
	fmt.println()
	fmt.println("Build a self-contained interactive HTML map from the exported code graph.")
	fmt.println("The map contains packages, files, symbols, call edges, lint findings and the")
	fmt.println("foreign/external import boundary. It does not embed source bodies.")
	fmt.println()
	fmt.println("Options:")
	fmt.println("  --db <path>      Graph database (default: .codegraph/olt.db, then codegraph.db)")
	fmt.println("  --out <path>     Output HTML (default: .codegraph/floorplan.html)")
	fmt.println("  --title <text>   Map title (default: project directory name)")
	fmt.println("  --open           Open the generated map in the default browser")
	fmt.println("  --json           Print the map data as JSON instead of writing HTML")
	fmt.println("  --help           Show this help")
	fmt.println()
	fmt.println("Before the first run:")
	fmt.println("  olt <target> --export-symbols")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  olt floorplan")
	fmt.println("  olt floorplan --db .codegraph/olt.db --open")
	fmt.println("  olt floorplan --out /tmp/olt-map.html --title \"My project\"")
}

@(private)
_fp_resolve_db :: proc(explicit: string) -> (path: string, exists: bool) {
	if explicit != "" {
		return explicit, os.is_file(explicit)
	}
	if os.is_file(GRAPH_DB_PATH) {
		return GRAPH_DB_PATH, true
	}
	if os.is_file(CODEGRAPH_DB_PATH) {
		return CODEGRAPH_DB_PATH, true
	}
	return GRAPH_DB_PATH, false
}

@(private)
_fp_open_path :: proc(path: string) {
	cmd: []string
	when ODIN_OS == .Darwin {
		cmd = []string{"open", path}
	} else when ODIN_OS == .Windows {
		cmd = []string{"cmd", "/c", "start", "", path}
	} else {
		cmd = []string{"xdg-open", path}
	}
	_, _, _, _ = os.process_exec(os.Process_Desc{command = cmd}, context.temp_allocator)
}

// =============================================================================
// Data
// =============================================================================

@(private)
_fp_render_html :: proc(data_json, title: string) -> string {
	html, _ := strings.replace_all(FLOORPLAN_HTML, "__OLT_FLOORPLAN_TITLE__", _fp_html_escape(title), context.temp_allocator)
	html, _ = strings.replace_all(html, "__OLT_FLOORPLAN_CSS__", FLOORPLAN_CSS, context.temp_allocator)
	html, _ = strings.replace_all(html, "__OLT_FLOORPLAN_DATA__", data_json, context.temp_allocator)
	html, _ = strings.replace_all(html, "__OLT_FLOORPLAN_JS__", FLOORPLAN_JS, context.temp_allocator)
	return html
}

@(private)
_fp_build_data :: proc(db: ^GraphDB, db_path, title, stale_path: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"schema_version":%d,`, FLOORPLAN_SCHEMA_VERSION)
	_fp_write_project(&b, db, db_path, title, stale_path)
	strings.write_byte(&b, ',')
	_fp_write_summary(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_packages(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_files(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_nodes(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_edges(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_imports(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_unresolved(&b, db)
	strings.write_byte(&b, ',')
	_fp_write_metadata(&b, db)
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

@(private)
_fp_write_project :: proc(b: ^strings.Builder, db: ^GraphDB, db_path, title, stale_path: string) {
	relative_stale := ""
	if stale_path != "" { relative_stale = graph_rel(db, stale_path) }

	strings.write_string(b, `"project":{`)
	fmt.sbprintf(b, `"name":%s,`, _fp_json_str(title))
	fmt.sbprintf(b, `"root":%s,`, _fp_json_str(db.root))
	fmt.sbprintf(b, `"db":%s,`, _fp_json_str(db_path))
	fmt.sbprintf(b, `"generated_at_ms":%d,`, _now_ms())
	fmt.sbprintf(b, `"olt_version":%s,`, _fp_json_str(OLT_VERSION))
	fmt.sbprintf(b, `"analysis_version":%d,`, ODIN_ANALYSIS_VERSION)
	fmt.sbprintf(b, `"stale_file":%s`, _fp_json_str(relative_stale))
	strings.write_byte(b, '}')
}

@(private)
_fp_write_summary :: proc(b: ^strings.Builder, db: ^GraphDB) {
	files      := _fp_scalar_int(db, "SELECT COUNT(*) FROM files;")
	packages   := _fp_scalar_int(db, "SELECT COUNT(*) FROM (SELECT DISTINCT dir,name FROM odin_package);")
	symbols    := _fp_scalar_int(db, "SELECT COUNT(*) FROM nodes WHERE kind <> 'file';")
	edges      := _fp_scalar_int(db, "SELECT COUNT(*) FROM edges;")
	unresolved := _fp_scalar_int(db, "SELECT COUNT(*) FROM unresolved_refs;")
	findings   := _fp_finding_count(db)
	fmt.sbprintf(b,
		`"summary":{{"files":%d,"packages":%d,"symbols":%d,"edges":%d,"unresolved":%d,"findings":%d}}`,
		files, packages, symbols, edges, unresolved, findings)
}

@(private)
_fp_write_packages :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"packages":[`)
	if s, ok := sq.db_prepare(db.conn, `SELECT DISTINCT dir,name FROM odin_package ORDER BY dir,name;`); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			dir  := sq.stmt_col_text(&s, 0)
			name := sq.stmt_col_text(&s, 1)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b, `{{"dir":%s,"name":%s}}`, _fp_json_str(dir), _fp_json_str(name))
			delete(dir)
			delete(name)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_files :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"files":[`)
	sql := `SELECT f.path,f.language,f.size,f.node_count,COALESCE(p.dir,''),COALESCE(p.name,'')
	        FROM files f LEFT JOIN odin_package p ON p.file_path=f.path
	        ORDER BY f.path;`
	if s, ok := sq.db_prepare(db.conn, sql); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			path  := sq.stmt_col_text(&s, 0)
			lang  := sq.stmt_col_text(&s, 1)
			size  := sq.stmt_col_int(&s, 2)
			nodes := sq.stmt_col_int(&s, 3)
			dir   := sq.stmt_col_text(&s, 4)
			pkg   := sq.stmt_col_text(&s, 5)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b,
				`{{"path":%s,"language":%s,"size":%d,"node_count":%d,"dir":%s,"package":%s}}`,
				_fp_json_str(path), _fp_json_str(lang), size, nodes, _fp_json_str(dir), _fp_json_str(pkg))
			delete(path); delete(lang); delete(dir); delete(pkg)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_nodes :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"nodes":[`)
	sql := `SELECT n.id,n.kind,n.name,n.qualified_name,n.file_path,n.language,
	               n.start_line,n.end_line,n.start_column,n.end_column,
	               COALESCE(n.signature,''),COALESCE(n.return_type,''),COALESCE(n.visibility,''),
	               n.is_exported,
	               COALESCE(i.memory_role,''),COALESCE(i.lint_violations,'[]')
	        FROM nodes n LEFT JOIN odin_node_info i ON i.node_id=n.id
	        ORDER BY n.file_path,n.start_line,n.start_column,n.kind,n.name;`
	if s, ok := sq.db_prepare(db.conn, sql); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			id        := sq.stmt_col_text(&s, 0)
			kind      := sq.stmt_col_text(&s, 1)
			name      := sq.stmt_col_text(&s, 2)
			qualified := sq.stmt_col_text(&s, 3)
			file      := sq.stmt_col_text(&s, 4)
			lang      := sq.stmt_col_text(&s, 5)
			start_ln  := sq.stmt_col_int(&s, 6)
			end_ln    := sq.stmt_col_int(&s, 7)
			start_col := sq.stmt_col_int(&s, 8)
			end_col   := sq.stmt_col_int(&s, 9)
			sig       := sq.stmt_col_text(&s, 10)
			ret       := sq.stmt_col_text(&s, 11)
			vis       := sq.stmt_col_text(&s, 12)
			exported  := sq.stmt_col_int(&s, 13) != 0
			role      := sq.stmt_col_text(&s, 14)
			lint      := sq.stmt_col_text(&s, 15)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b,
				`{{"id":%s,"kind":%s,"name":%s,"qualified":%s,"file":%s,"language":%s,`+
				`"start_line":%d,"end_line":%d,"start_col":%d,"end_col":%d,`+
				`"signature":%s,"return_type":%s,"visibility":%s,"exported":%v,`+
				`"memory_role":%s,"lint":`,
				_fp_json_str(id), _fp_json_str(kind), _fp_json_str(name), _fp_json_str(qualified),
				_fp_json_str(file), _fp_json_str(lang),
				start_ln, end_ln, start_col, end_col,
				_fp_json_str(sig), _fp_json_str(ret), _fp_json_str(vis), exported,
				_fp_json_str(role))
			_fp_write_lint_array(b, lint)
			strings.write_byte(b, '}')
			delete(id); delete(kind); delete(name); delete(qualified); delete(file); delete(lang)
			delete(sig); delete(ret); delete(vis); delete(role); delete(lint)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_edges :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"edges":[`)
	if s, ok := sq.db_prepare(db.conn, `SELECT source,target,kind,COALESCE(line,0),COALESCE(col,0) FROM edges ORDER BY id;`); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			source := sq.stmt_col_text(&s, 0)
			target := sq.stmt_col_text(&s, 1)
			kind   := sq.stmt_col_text(&s, 2)
			line   := sq.stmt_col_int(&s, 3)
			col    := sq.stmt_col_int(&s, 4)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b, `{{"source":%s,"target":%s,"kind":%s,"line":%d,"col":%d}}`,
				_fp_json_str(source), _fp_json_str(target), _fp_json_str(kind), line, col)
			delete(source); delete(target); delete(kind)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_imports :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"imports":[`)
	sql := `SELECT file_path,line,path,COALESCE(alias,''),COALESCE(dir,''),
	               (EXISTS (SELECT 1 FROM odin_package p WHERE p.dir = odin_import.dir))
	        FROM odin_import ORDER BY file_path,line,path;`
	if s, ok := sq.db_prepare(db.conn, sql); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			file     := sq.stmt_col_text(&s, 0)
			line     := sq.stmt_col_int(&s, 1)
			path     := sq.stmt_col_text(&s, 2)
			alias    := sq.stmt_col_text(&s, 3)
			dir      := sq.stmt_col_text(&s, 4)
			internal := sq.stmt_col_int(&s, 5) != 0
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b, `{{"file":%s,"line":%d,"path":%s,"alias":%s,"dir":%s,"internal":%v}}`,
				_fp_json_str(file), line, _fp_json_str(path), _fp_json_str(alias), _fp_json_str(dir), internal)
			delete(file); delete(path); delete(alias); delete(dir)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_unresolved :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"unresolved":[`)
	sql := `SELECT from_node_id,reference_name,reference_kind,file_path,line,COALESCE(col,0)
	        FROM unresolved_refs ORDER BY file_path,line,col,reference_name;`
	if s, ok := sq.db_prepare(db.conn, sql); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			from  := sq.stmt_col_text(&s, 0)
			name  := sq.stmt_col_text(&s, 1)
			kind  := sq.stmt_col_text(&s, 2)
			file  := sq.stmt_col_text(&s, 3)
			line  := sq.stmt_col_int(&s, 4)
			col   := sq.stmt_col_int(&s, 5)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b, `{{"from":%s,"name":%s,"kind":%s,"file":%s,"line":%d,"col":%d}}`,
				_fp_json_str(from), _fp_json_str(name), _fp_json_str(kind),
				_fp_json_str(file), line, col)
			delete(from); delete(name); delete(kind); delete(file)
		}
	}
	strings.write_byte(b, ']')
}

@(private)
_fp_write_metadata :: proc(b: ^strings.Builder, db: ^GraphDB) {
	strings.write_string(b, `"metadata":{`)
	if s, ok := sq.db_prepare(db.conn, `SELECT key,value FROM project_metadata ORDER BY key;`); ok {
		defer sq.stmt_finalize(&s)
		first := true
		for sq.stmt_step(&s) {
			key   := sq.stmt_col_text(&s, 0)
			value := sq.stmt_col_text(&s, 1)
			if !first { strings.write_byte(b, ',') }
			first = false
			fmt.sbprintf(b, `%s:%s`, _fp_json_str(key), _fp_json_str(value))
			delete(key); delete(value)
		}
	}
	strings.write_byte(b, '}')
}

// =============================================================================
// Utilities
// =============================================================================

@(private)
_fp_scalar_int :: proc(db: ^GraphDB, query: string) -> int {
	if s, ok := sq.db_prepare(db.conn, query); ok {
		defer sq.stmt_finalize(&s)
		if sq.stmt_step(&s) { return sq.stmt_col_int(&s, 0) }
	}
	return 0
}

// Count distinct (node, rule) findings. odin_node_info can hold the same rule
// more than once for a node; the map shows one badge per rule.
@(private)
_fp_finding_count :: proc(db: ^GraphDB) -> int {
	return _fp_scalar_int(db, `SELECT COUNT(*) FROM (
		SELECT i.node_id, j.value
		FROM odin_node_info i, json_each(i.lint_violations) j
		WHERE i.lint_violations IS NOT NULL AND json_valid(i.lint_violations)
		GROUP BY i.node_id, j.value
	);`)
}

@(private)
_fp_write_lint_array :: proc(b: ^strings.Builder, raw: string) {
	trimmed := strings.trim_space(raw)
	if len(trimmed) >= 2 && trimmed[0] == '[' && trimmed[len(trimmed)-1] == ']' {
		strings.write_string(b, trimmed)
	} else {
		strings.write_string(b, "[]")
	}
}

@(private)
_fp_json_str :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_byte(&sb, '"')
	for c in s {
		switch c {
		case '"':  strings.write_string(&sb, `\"`)
		case '\\': strings.write_string(&sb, `\\`)
		case '\n': strings.write_string(&sb, `\n`)
		case '\r': strings.write_string(&sb, `\r`)
		case '\t': strings.write_string(&sb, `\t`)
		case '<':  strings.write_string(&sb, `\u003c`)
		case '>':  strings.write_string(&sb, `\u003e`)
		case '&':  strings.write_string(&sb, `\u0026`)
		case:
			if c < 0x20 {
				fmt.sbprintf(&sb, `\u%04x`, int(c))
			} else {
				strings.write_rune(&sb, c)
			}
		}
	}
	strings.write_byte(&sb, '"')
	return strings.to_string(sb)
}

@(private)
_fp_html_escape :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for c in s {
		switch c {
		case '&': strings.write_string(&sb, "&amp;")
		case '<': strings.write_string(&sb, "&lt;")
		case '>': strings.write_string(&sb, "&gt;")
		case '"': strings.write_string(&sb, "&quot;")
		case '\'': strings.write_string(&sb, "&#39;")
		case: strings.write_rune(&sb, c)
		}
	}
	return strings.to_string(sb)
}

@(private)
_fp_project_name :: proc(root: string) -> string {
	trimmed := strings.trim_right(root, "/\\")
	if trimmed == "" { return "code graph" }
	if i := strings.last_index_byte(trimmed, '/'); i >= 0 {
		return trimmed[i+1:]
	}
	return trimmed
}

@(private)
_fp_mkdir_p :: proc(dir: string) -> bool {
	if dir == "" || dir == "." || dir == "/" { return true }
	if os.is_dir(dir) { return true }
	parent := filepath_dir(dir)
	if parent != dir { _fp_mkdir_p(parent) }
	err := os.make_directory(dir)
	return err == nil || os.is_dir(dir)
}
