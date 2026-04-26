// b002-STR-PackageName.odin — B002/B003: package-name consistency rules.
// B002 flags files whose package declaration doesn't match the directory majority;
// B003 flags a subdirectory that reuses its parent's package name.
package core

import "core:os"
import "core:path/filepath"
import "core:strings"

// =============================================================================
// B002: Package Name Consistency
// B003: Subfolder Shares Parent Package Name
// =============================================================================
//
// Both rules operate at PACKAGE SCOPE — they require seeing all .odin files
// in a directory together.  They cannot be implemented at file scope.
//
// B002 — Package Name Consistency
//   All .odin files in a directory MUST share the same package declaration.
//   Different package names in one directory is a compiler error.
//   Algorithm: majority wins; outlier files are flagged.
//   Exception: "package foo_test" is a valid sibling of "package foo".
//
// B003 — Subfolder Shares Parent Package Name
//   In Odin, subfolders are always separate packages regardless of name.
//   If src/graphics/ uses "package graphics" and src/graphics/utils/ also
//   uses "package graphics", the two are NOT the same package — the compiler
//   treats them as distinct and utils must be explicitly imported.
//   This is almost always an organisational mistake.
//
// Category: STRUCTURAL (B002 = error tier, B003 = warning tier)
// =============================================================================

// DirPackageInfo records the resolved package name for one directory.
DirPackageInfo :: struct {
    dir:          string,
    package_name: string,  // majority name (empty if no files)
}

// read_package_declaration returns the package name declared in the given
// .odin file.  Skips leading blank lines and // comments.
// Returns "" if no package declaration is found.
read_package_declaration :: proc(file_path: string) -> string {
    data, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil do return ""
    defer delete(data)

    text := string(data)
    for len(text) > 0 {
        // Find end of current line.
        nl := strings.index_byte(text, '\n')
        line: string
        if nl < 0 {
            line = text
            text = ""
        } else {
            line = text[:nl]
            text = text[nl + 1:]
        }
        line = strings.trim_space(line)
        if line == "" do continue
        if strings.has_prefix(line, "//") do continue
        if strings.has_prefix(line, "/*") do continue  // block comment start — skip

        // First non-blank, non-comment line must be the package declaration.
        if strings.has_prefix(line, "package ") {
            name := strings.trim_space(line[len("package "):])
            // Strip any trailing comment.
            if ci := strings.index(name, "//"); ci >= 0 {
                name = strings.trim_space(name[:ci])
            }
            return strings.clone(name)
        }
        break  // non-package first statement — malformed file
    }
    return ""
}

// b002_check_directory checks that all files in dir agree on a package name.
// majority_name is pre-computed by the caller (see b002_majority_name).
// test_base is the non-test package name (e.g. "graphics" for "graphics_test").
// Files whose declaration matches majority_name or is the _test variant are OK.
b002_check_directory :: proc(
    files:         []string,
    majority_name: string,
) -> []Diagnostic {
    diags := make([dynamic]Diagnostic)
    if majority_name == "" || len(files) <= 1 do return diags[:]

    test_variant := strings.concatenate([]string{majority_name, "_test"})
    defer delete(test_variant)

    for file_path in files {
        pkg := read_package_declaration(file_path)
        defer delete(pkg)
        if pkg == "" || pkg == majority_name || pkg == test_variant do continue

        // This file is the outlier.
        msg := strings.concatenate([]string{
            `package "`, pkg, `" — expected "`, majority_name,
            `" (majority in this directory)`,
        })
        append(&diags, Diagnostic{
            file      = strings.clone(file_path),
            line      = 1,
            column    = 1,
            rule_id   = "B002",
            tier      = "structural",
            message   = msg,
            fix       = strings.concatenate([]string{`Change to: package `, majority_name}),
            has_fix   = true,
            diag_type = DiagnosticType.VIOLATION,
        })
    }
    return diags[:]
}

// b002_majority_name returns the most common package name among files.
// _test variants are excluded from the vote.
// Returns "" if no files have a readable package declaration.
b002_majority_name :: proc(files: []string) -> string {
    counts := make(map[string]int)
    defer {
        for k in counts { delete(k) }
        delete(counts)
    }

    for file_path in files {
        pkg := read_package_declaration(file_path)
        defer delete(pkg)
        if pkg == "" do continue
        if strings.has_suffix(pkg, "_test") do continue  // exclude test variants from vote
        cloned := strings.clone(pkg)
        counts[cloned] += 1
    }

    best_name  := ""
    best_count := 0
    for name, count in counts {
        if count > best_count {
            best_count = count
            best_name  = name
        }
    }
    return strings.clone(best_name)
}

// b003_check_subdirs checks whether any subdirectory in dir_packages shares
// a package name with its immediate parent directory.
// dir_packages maps directory path → resolved majority package name.
b003_check_subdirs :: proc(
    dir_packages: map[string]string,
    dir_files:    map[string][dynamic]string,
) -> []Diagnostic {
    diags := make([dynamic]Diagnostic)

    for child_dir, child_pkg in dir_packages {
        if child_pkg == "" do continue
        parent_dir := filepath.dir(child_dir)
        if parent_dir == child_dir do continue  // root — no parent

        parent_pkg, parent_ok := dir_packages[parent_dir]
        if !parent_ok || parent_pkg == "" do continue
        if child_pkg != parent_pkg do continue

        // Subfolder shares parent's package name — warn the first file.
        files, has_files := dir_files[child_dir]
        if !has_files || len(files) == 0 do continue

        first_file := files[0]
        msg := strings.concatenate([]string{
            `package "`, child_pkg, `" — subfolder "`,
            filepath.base(child_dir),
            `" is a separate Odin package from parent "`,
            filepath.base(parent_dir),
            `"; did you mean a distinct package name?`,
        })
        append(&diags, Diagnostic{
            file      = strings.clone(first_file),
            line      = 1,
            column    = 1,
            rule_id   = "B003",
            tier      = "structural",
            message   = msg,
            has_fix   = false,
            diag_type = DiagnosticType.VIOLATION,
        })
    }
    return diags[:]
}
