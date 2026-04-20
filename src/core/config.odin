package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// odin-lint.toml — project-level configuration
// =============================================================================
//
// Loaded from the closest odin-lint.toml found in the search path.
// When absent, domain auto-detection heuristics are applied.
//
// Example odin-lint.toml:
//
//   [domains]
//   ffi             = true   # enable C011 FFI safety rules
//   odin_2026       = true   # enable C009, C010 migration rules
//   semantic_naming = false  # enable C012 ownership hints (opt-in)
//
//   [target]
//   odin_version = "dev-2026-04"
// =============================================================================

// OdinLintConfig holds the parsed project configuration.
OdinLintConfig :: struct {
    // Domain flags — control which rule groups are active.
    ffi_domain:             bool, // C011 FFI safety rules
    odin_2026_domain:       bool, // C009, C010 migration rules
    semantic_naming_domain: bool, // C012 semantic ownership hints
    dead_code_domain:       bool, // C014, C015 dead code (opt-in, project-wide)

    // Per-rule flags for scope-aware naming rules (C016–C018).
    naming_c016: bool, // C016 local snake_case  (default: true)
    naming_c017: bool, // C017 global camelCase  (default: false — opt-in)
    naming_c018: bool, // C018 proc visibility   (default: false — opt-in, conflicts with C003)

    // Target settings.
    odin_version: string, // e.g. "dev-2026-04"

    // Internal: whether a toml file was found and loaded.
    loaded: bool,
}

// default_config returns the default configuration (all mainstream rules on).
default_config :: proc() -> OdinLintConfig {
    return OdinLintConfig{
        ffi_domain             = true,
        odin_2026_domain       = true,
        semantic_naming_domain = false,
        dead_code_domain       = false,  // opt-in: project-wide dead code (C014, C015)
        naming_c016            = true,   // standard rule — on by default
        naming_c017            = false,  // opt-in: camelCase globals
        naming_c018            = false,  // opt-in: visibility-based proc naming
        odin_version           = "",
        loaded                 = false,
    }
}

// load_project_config searches for odin-lint.toml in the given directories
// (or parent dirs of file targets) and the current working directory.
// Falls back to defaults + auto-detection if no file is found.
load_project_config :: proc(targets: []string) -> OdinLintConfig {
    cfg := default_config()

    // Collect unique directories to search.
    seen_dirs := make(map[string]bool)
    defer delete(seen_dirs)
    search_dirs := make([dynamic]string)
    defer delete(search_dirs)

    for t in targets {
        dir := t if os.is_dir(t) else filepath_dir(t)
        if dir == "" { continue }
        if dir not_in seen_dirs {
            seen_dirs[dir] = true
            append(&search_dirs, dir)
        }
    }

    // Look for odin-lint.toml in each search directory.
    for dir in search_dirs {
        toml_path := strings.join([]string{dir, "odin-lint.toml"}, "/")
        defer delete(toml_path)
        if os.is_file(toml_path) {
            ok := parse_toml_config(toml_path, &cfg)
            if ok {
                cfg.loaded = true
                return cfg
            }
        }
    }

    // Also check current working directory.
    if os.is_file("odin-lint.toml") {
        ok := parse_toml_config("odin-lint.toml", &cfg)
        if ok {
            cfg.loaded = true
            return cfg
        }
    }

    // No toml found — apply auto-detection heuristics.
    apply_auto_detection(&cfg, search_dirs[:])
    return cfg
}

// apply_auto_detection sets domain flags based on project structure heuristics.
@(private)
apply_auto_detection :: proc(cfg: ^OdinLintConfig, search_dirs: []string) {
    // If ffi/ directory exists at project root: enable ffi domain.
    if os.is_dir("ffi") {
        cfg.ffi_domain = true
    }
    // Check inside each search dir too.
    for dir in search_dirs {
        ffi_path := strings.join([]string{dir, "ffi"}, "/")
        defer delete(ffi_path)
        if os.is_dir(ffi_path) {
            cfg.ffi_domain = true
        }
    }
}

// parse_toml_config reads and parses an odin-lint.toml file.
// Only the keys we care about are parsed; unknown keys are silently ignored.
@(private)
parse_toml_config :: proc(path: string, cfg: ^OdinLintConfig) -> bool {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil { return false }
    defer delete(data)

    content := string(data)
    lines   := strings.split(content, "\n")
    defer delete(lines)

    current_section := ""

    for raw_line in lines {
        line := strings.trim(raw_line, " \t\r")

        // Skip blanks and comments.
        if len(line) == 0 || strings.has_prefix(line, "#") { continue }

        // Section header.
        if strings.has_prefix(line, "[") && strings.has_suffix(line, "]") {
            current_section = line[1 : len(line)-1]
            continue
        }

        // Key = value.
        eq := strings.index(line, "=")
        if eq < 0 { continue }

        key := strings.trim(line[:eq], " \t")
        val := strings.trim(line[eq+1:], " \t")
        // Strip inline comments.
        if hash := strings.index(val, " #"); hash >= 0 {
            val = strings.trim(val[:hash], " \t")
        }

        switch current_section {
        case "domains":
            switch key {
            case "ffi":             cfg.ffi_domain             = val == "true"
            case "odin_2026":       cfg.odin_2026_domain       = val == "true"
            case "semantic_naming": cfg.semantic_naming_domain = val == "true"
            case "dead_code":       cfg.dead_code_domain       = val == "true"
            }
        case "naming":
            switch key {
            case "c016": cfg.naming_c016 = val == "true"
            case "c017": cfg.naming_c017 = val == "true"
            case "c018": cfg.naming_c018 = val == "true"
            }
        case "target":
            if key == "odin_version" {
                // Strip surrounding quotes if present.
                v := strings.trim(val, "\"'")
                cfg.odin_version = strings.clone(v)
            }
        }
    }

    return true
}

// config_domain_enabled returns whether a rule should be active according to
// the project config. Called alongside rule_enabled for domain-gated rules.
// When no config was loaded (zero-value OdinLintConfig), defaults from
// default_config() are used so callers that pass {} still get correct behaviour.
config_domain_enabled :: proc(rule_id: string, cfg: OdinLintConfig) -> bool {
    effective := cfg
    if !cfg.loaded { effective = default_config() }

    switch rule_id {
    case "C009", "C010":
        return effective.odin_2026_domain
    case "C011":
        return effective.ffi_domain
    case "C012":
        return effective.semantic_naming_domain
    case "C014", "C015":
        return effective.dead_code_domain
    case "C016":
        return effective.naming_c016
    case "C017":
        return effective.naming_c017
    case "C018":
        return effective.naming_c018
    }
    return true // all other rules: not domain-gated
}

// filepath_dir returns the directory component of a path (everything before the
// last '/'). Returns "." if there is no directory component.
@(private)
filepath_dir :: proc(path: string) -> string {
    for i := len(path) - 1; i >= 0; i -= 1 {
        if path[i] == '/' || path[i] == '\\' {
            if i == 0 { return "/" }
            return path[:i]
        }
    }
    return "."
}

// print_config_summary prints the active configuration when --verbose is used.
// Currently called only when a toml file was loaded.
print_config_summary :: proc(cfg: OdinLintConfig) {
    if !cfg.loaded { return }
    fmt.eprintfln("config: odin-lint.toml loaded")
    fmt.eprintfln("  domains: ffi=%v odin_2026=%v semantic_naming=%v dead_code=%v",
        cfg.ffi_domain, cfg.odin_2026_domain, cfg.semantic_naming_domain, cfg.dead_code_domain)
    fmt.eprintfln("  naming:  c016=%v c017=%v c018=%v",
        cfg.naming_c016, cfg.naming_c017, cfg.naming_c018)
    if cfg.odin_version != "" {
        fmt.eprintfln("  target odin_version: %s", cfg.odin_version)
    }
}
