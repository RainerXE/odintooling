package core

import "core:fmt"
import "core:strings"

// =============================================================================
// Output — text, JSON, SARIF formatters
// =============================================================================

// emit_or_collect either emits a diagnostic immediately (text mode, collector==nil)
// or appends it to the collector (json/sarif mode). Returns 1 if non-empty.
emit_or_collect :: proc(d: Diagnostic, collector: ^[dynamic]Diagnostic) -> int {
    if d.message == "" { return 0 }
    if collector != nil {
        append(collector, d)
    } else {
        emitDiagnostic(d)
    }
    return 1
}

// json_write_string writes a JSON-escaped, double-quoted string into b.
@(private)
json_write_string :: proc(b: ^strings.Builder, s: string) {
    strings.write_byte(b, '"')
    for c in s {
        switch c {
        case '"':  strings.write_string(b, "\\\"")
        case '\\': strings.write_string(b, "\\\\")
        case '\n': strings.write_string(b, "\\n")
        case '\r': strings.write_string(b, "\\r")
        case '\t': strings.write_string(b, "\\t")
        case:
            if c < 0x20 {
                fmt.sbprintf(b, "\\u%04x", int(c))
            } else {
                strings.write_rune(b, c)
            }
        }
    }
    strings.write_byte(b, '"')
}

// emit_json writes all diagnostics as a JSON array to stdout.
// Schema: [{"file":str,"line":int,"column":int,"rule_id":str,"error_class":str,"tier":str,"message":str,"fix":str?}]
emit_json :: proc(diags: []Diagnostic) {
    b := strings.builder_make()
    defer strings.builder_destroy(&b)

    strings.write_string(&b, "[\n")
    for d, i in diags {
        if i > 0 { strings.write_string(&b, ",\n") }
        strings.write_string(&b, "  {")
        strings.write_string(&b, `"file":`)
        json_write_string(&b, d.file)
        fmt.sbprintf(&b, `,"line":%d,"column":%d`, d.line, d.column)
        strings.write_string(&b, `,"rule_id":`)
        json_write_string(&b, d.rule_id)
        strings.write_string(&b, `,"error_class":`)
        json_write_string(&b, rule_id_to_error_class(d.rule_id))
        strings.write_string(&b, `,"tier":`)
        json_write_string(&b, d.tier)
        strings.write_string(&b, `,"message":`)
        json_write_string(&b, d.message)
        if d.has_fix {
            strings.write_string(&b, `,"fix":`)
            json_write_string(&b, d.fix)
        }
        strings.write_string(&b, "}")
    }
    strings.write_string(&b, "\n]\n")
    fmt.print(strings.to_string(b))
}

// sarif_level maps a Diagnostic to the appropriate SARIF result level.
@(private)
sarif_level :: proc(d: Diagnostic) -> string {
    switch d.diag_type {
    case .INFO:           return "note"
    case .INTERNAL_ERROR: return "error"
    case .CONTEXTUAL:     return "warning"
    case .VIOLATION, .NONE:
        return "warning" if d.tier == "style" else "error"
    }
    return "error"
}

// emit_sarif writes all diagnostics as a SARIF 2.1.0 document to stdout.
// Compatible with GitHub Actions code scanning and VS Code SARIF viewer.
emit_sarif :: proc(diags: []Diagnostic) {
    b := strings.builder_make()
    defer strings.builder_destroy(&b)

    strings.write_string(&b, "{\n")
    strings.write_string(&b, "  \"$schema\": \"https://json.schemastore.org/sarif-2.1.0.json\",\n")
    strings.write_string(&b, "  \"version\": \"2.1.0\",\n")
    strings.write_string(&b, "  \"runs\": [\n    {\n")
    strings.write_string(&b, "      \"tool\": {\"driver\": {\"name\": \"odin-lint\", \"version\": ")
    json_write_string(&b, ODIN_LINT_VERSION)
    strings.write_string(&b, ", \"informationUri\": \"https://github.com/anthropics/claude-code/issues\"}},\n")
    strings.write_string(&b, "      \"results\": [")

    for d, i in diags {
        if i > 0 { strings.write_string(&b, ",") }
        strings.write_string(&b, "\n        {\n")
        strings.write_string(&b, "          \"ruleId\": ")
        json_write_string(&b, d.rule_id)
        fmt.sbprintf(&b, ",\n          \"level\": \"%s\",\n", sarif_level(d))
        strings.write_string(&b, "          \"message\": {\"text\": ")
        json_write_string(&b, d.message)
        strings.write_string(&b, "},\n")
        strings.write_string(&b, "          \"locations\": [{\n")
        strings.write_string(&b, "            \"physicalLocation\": {\n")
        strings.write_string(&b, "              \"artifactLocation\": {\"uri\": ")
        json_write_string(&b, d.file)
        strings.write_string(&b, "},\n")
        strings.write_string(&b, "              \"region\": {\"startLine\": ")
        fmt.sbprintf(&b, "%d", d.line)
        strings.write_string(&b, ", \"startColumn\": ")
        fmt.sbprintf(&b, "%d", d.column)
        strings.write_string(&b, "}\n")
        strings.write_string(&b, "            }\n          }]")
        if d.has_fix {
            strings.write_string(&b, ",\n          \"fixes\": [{\"description\": {\"text\": ")
            json_write_string(&b, d.fix)
            strings.write_string(&b, "}}]")
        }
        strings.write_string(&b, "\n        }")
    }

    strings.write_string(&b, "\n      ]\n    }\n  ]\n}\n")
    fmt.print(strings.to_string(b))
}
