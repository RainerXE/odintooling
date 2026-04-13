package core

import "core:fmt"
import "core:os"
import "core:strings"

// =============================================================================
// Scanner — collect .odin file paths from file and directory targets
// =============================================================================

// collect_odin_files expands a list of file/directory targets into a flat
// list of .odin file paths. The caller owns the returned slice and each
// string in it (all are cloned).
collect_odin_files :: proc(
    targets:        []string,
    recursive:      bool,
    include_vendor: bool,
) -> [dynamic]string {
    files := make([dynamic]string)
    for target in targets {
        if os.is_dir(target) {
            if recursive {
                fmt.eprintfln(
                    "Warning: scanning '%s' recursively. Use --non-recursive to scan top-level only.",
                    target,
                )
            }
            walk_dir(target, recursive, include_vendor, &files)
        } else if strings.has_suffix(target, ".odin") {
            append(&files, strings.clone(target))
        } else {
            fmt.eprintfln("warning: '%s' is not a .odin file or directory, skipping", target)
        }
    }
    return files
}

// walk_dir appends .odin files found in dir_path to files.
// Recurses into subdirectories when recursive=true; skips vendor/ and hidden dirs.
walk_dir :: proc(
    dir_path:       string,
    recursive:      bool,
    include_vendor: bool,
    files:          ^[dynamic]string,
) {
    handle, open_err := os.open(dir_path)
    if open_err != nil {
        fmt.eprintfln("warning: cannot open '%s', skipping", dir_path)
        return
    }
    defer os.close(handle)

    infos, read_err := os.read_dir(handle, -1, context.allocator)
    if read_err != nil {
        fmt.eprintfln("warning: cannot read directory '%s', skipping", dir_path)
        return
    }
    defer {
        for info in infos { os.file_info_delete(info, context.allocator) }
        delete(infos)
    }

    for info in infos {
        if os.is_dir(info.fullpath) {
            if !recursive { continue }
            if info.name == "vendor" && !include_vendor { continue }
            if len(info.name) > 0 && info.name[0] == '.' { continue }
            walk_dir(info.fullpath, recursive, include_vendor, files)
        } else if strings.has_suffix(info.name, ".odin") {
            append(files, strings.clone(info.fullpath))
        }
    }
}
