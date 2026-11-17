// update.odin — `olt update`: check GitHub for a newer release, verify it, and install it in place.
//
// The download and unpack steps shell out to curl and tar because both ship with macOS, Linux and
// Windows 10. The archive's SHA-256 is checked against the digest the GitHub API reports for it, so a
// truncated or tampered download is refused before anything replaces the running binary.
package core

import "core:crypto/sha2"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

UPDATE_LATEST_URL :: "https://api.github.com/repos/RainerXE/odintooling/releases/latest"
UPDATE_USER_AGENT :: "olt-update"

UpdateOptions :: struct {
    check: bool,
    force: bool,
    help:  bool,
}

@(private)
Update_Asset :: struct {
    name:                 string `json:"name"`,
    browser_download_url: string `json:"browser_download_url"`,
    digest:               string `json:"digest"`,
    size:                 i64    `json:"size"`,
}

@(private)
Update_Release :: struct {
    tag_name: string         `json:"tag_name"`,
    assets:   []Update_Asset `json:"assets"`,
}

@(private)
Update_Version :: struct {
    major, minor, patch: int,
}

// run_update_command runs `olt update [--check] [--force]`. Exit codes: 0 success or up to date,
// 1 update available (with --check only), 2 usage or install failure.
run_update_command :: proc(args: []string) -> int {
    opts, ok := _update_parse_args(args)
    if !ok { return 2 }
    if opts.help {
        _update_print_help()
        return 0
    }

    plat := _update_platform_tag()
    if plat == "" {
        fmt.eprintfln("olt update: no prebuilt release for this platform (%v/%v).", ODIN_OS, ODIN_ARCH)
        fmt.eprintln("  Build from source: https://github.com/RainerXE/odintooling#build-from-source")
        return 2
    }

    tmp_root, terr := os.temp_directory(context.allocator)
    if terr != nil {
        fmt.eprintfln("olt update: cannot find a temporary directory: %v", terr)
        return 2
    }
    defer delete(tmp_root)

    tmp := fmt.aprintf("%s/olt-update-%d", tmp_root, os.get_pid())
    defer {
        _ = os.remove_all(tmp)
        delete(tmp)
    }
    if merr := os.make_directory_all(tmp); merr != nil {
        fmt.eprintfln("olt update: cannot create %s: %v", tmp, merr)
        return 2
    }

    rel, fetched := _update_fetch_release(tmp)
    if !fetched { return 2 }

    remote, rok := _update_parse_version(rel.tag_name)
    if !rok {
        fmt.eprintfln("olt update: cannot read the release tag '%s'", rel.tag_name)
        return 2
    }
    local, lok := _update_parse_version(OLT_VERSION)
    if !lok {
        fmt.eprintfln("olt update: cannot read the built-in version '%s'", OLT_VERSION)
        return 2
    }

    remote_tag := rel.tag_name
    if strings.has_prefix(remote_tag, "v") { remote_tag = remote_tag[1:] }

    cmp := _update_compare_version(remote, local)
    fmt.printfln("  installed: %s", OLT_VERSION)
    fmt.printfln("  latest:    %s", remote_tag)

    if cmp < 0 {
        fmt.printfln("olt %s is newer than the latest release (%s); nothing to do.", OLT_VERSION, remote_tag)
        return 0
    }
    if cmp == 0 && !opts.force {
        fmt.printfln("olt %s is up to date.", OLT_VERSION)
        return 0
    }
    if opts.check {
        if cmp > 0 {
            fmt.println("A newer release is available. Run 'olt update' to install it.")
            return 1
        }
        fmt.printfln("olt %s is up to date.", OLT_VERSION)
        return 0
    }

    ext := _update_archive_ext()
    asset_name := fmt.aprintf("olt-%s-%s.%s", remote_tag, plat, ext)
    defer delete(asset_name)

    asset: ^Update_Asset
    for i in 0 ..< len(rel.assets) {
        if rel.assets[i].name == asset_name {
            asset = &rel.assets[i]
            break
        }
    }
    if asset == nil {
        fmt.eprintfln("olt update: release %s has no asset '%s'.", rel.tag_name, asset_name)
        fmt.eprintln("  Published assets:")
        for a in rel.assets {
            fmt.eprintfln("    %s", a.name)
        }
        return 2
    }

    archive := fmt.aprintf("%s/%s", tmp, asset_name)
    defer delete(archive)

    fmt.printfln("  downloading %s (%d bytes)...", asset_name, asset.size)
    if !_update_run({"curl", "-fsSL", "-o", archive, asset.browser_download_url}, "the download") {
        return 2
    }

    digest := strings.trim(asset.digest, " \t\r\n")
    if digest == "" {
        fmt.eprintln("  warning: this release publishes no SHA-256 digest; skipping the integrity check.")
    } else if !_update_verify_sha256(archive, digest) {
        fmt.eprintfln("olt update: SHA-256 mismatch for %s — the download was discarded.", asset_name)
        return 2
    } else {
        fmt.println("  verified SHA-256")
    }

    extract_dir := fmt.aprintf("%s/extract", tmp)
    defer delete(extract_dir)
    if merr := os.make_directory_all(extract_dir); merr != nil {
        fmt.eprintfln("olt update: cannot create %s: %v", extract_dir, merr)
        return 2
    }

    when ODIN_OS == .Windows {
        ok = _update_run({"tar", "-xf", archive, "-C", extract_dir}, "the extraction")
    } else {
        ok = _update_run({"tar", "-xzf", archive, "-C", extract_dir}, "the extraction")
    }
    if !ok { return 2 }

    exe_name := "olt"
    when ODIN_OS == .Windows { exe_name = "olt.exe" }
    src := fmt.aprintf("%s/olt-%s-%s/%s", extract_dir, remote_tag, plat, exe_name)
    defer delete(src)
    if !os.is_file(src) {
        fmt.eprintfln("olt update: the archive did not contain %s", src)
        return 2
    }

    dest, derr := os.get_executable_path(context.allocator)
    if derr != nil {
        fmt.eprintfln("olt update: cannot locate the running binary: %v", derr)
        return 2
    }
    defer delete(dest)

    fmt.printfln("  installing %s", dest)
    if !_update_replace_binary(src, dest) {
        _update_print_manual(asset.browser_download_url, asset_name, remote_tag, plat, dest)
        return 2
    }

    if cmp > 0 {
        fmt.printfln("✓ updated olt %s → %s", OLT_VERSION, remote_tag)
    } else {
        fmt.printfln("✓ reinstalled olt %s", remote_tag)
    }
    fmt.println("  Restart any running olt-mcp/olt-lsp processes to pick it up.")
    return 0
}

// _update_parse_args reads the flags accepted after `olt update`.
@(private)
_update_parse_args :: proc(args: []string) -> (opts: UpdateOptions, ok: bool) {
    for arg in args {
        switch {
        case arg == "--check": opts.check = true
        case arg == "--force": opts.force = true
        case arg == "--help" || arg == "-h": opts.help = true
        case:
            fmt.eprintfln("olt update: unknown argument '%s'", arg)
            fmt.eprintln("usage: olt update [--check] [--force]")
            return opts, false
        }
    }
    if opts.check && opts.force {
        fmt.eprintln("olt update: --check and --force cannot be combined")
        return opts, false
    }
    return opts, true
}

@(private)
_update_print_help :: proc() {
    fmt.println("Usage: olt update [--check] [--force]")
    fmt.println()
    fmt.println("Checks https://github.com/RainerXE/odintooling/releases/latest and installs the")
    fmt.println("newest prebuilt binary for this platform over the running one. The archive's")
    fmt.println("SHA-256 is verified against the GitHub API digest before anything is replaced.")
    fmt.println()
    fmt.println("  --check   Report only: exit 0 if current, 1 if a newer release exists, 2 on error")
    fmt.println("  --force   Reinstall the latest release even when the version matches")
    fmt.println("  --help    Show this message")
}

// _update_platform_tag maps the compile-time target to the release asset suffix.
// Only platforms that actually publish an archive return a tag.
@(private)
_update_platform_tag :: proc() -> string {
    when ODIN_OS == .Darwin {
        when ODIN_ARCH == .arm64 { return "macos-arm64" }
        else { return "" }
    } else when ODIN_OS == .Linux {
        when ODIN_ARCH == .amd64 { return "linux-x86_64" }
        else { return "" }
    } else when ODIN_OS == .Windows {
        when ODIN_ARCH == .amd64 { return "windows-x86_64" }
        else { return "" }
    } else {
        return ""
    }
}

@(private)
_update_archive_ext :: proc() -> string {
    when ODIN_OS == .Windows { return "zip" }
    else { return "tar.gz" }
}

// _update_fetch_release downloads releases/latest and unmarshals the fields the updater needs.
@(private)
_update_fetch_release :: proc(tmp: string) -> (rel: Update_Release, ok: bool) {
    path := fmt.aprintf("%s/release.json", tmp)
    defer delete(path)

    ua := fmt.aprintf("User-Agent: %s", UPDATE_USER_AGENT)
    defer delete(ua)

    fmt.printfln("Checking %s ...", UPDATE_LATEST_URL)
    if !_update_run({"curl", "-fsSL", "-H", "Accept: application/vnd.github+json", "-H", ua, "-o", path, UPDATE_LATEST_URL}, "the GitHub API request") {
        return rel, false
    }

    data, rerr := os.read_entire_file(path, context.allocator)
    if rerr != nil {
        fmt.eprintfln("olt update: cannot read the API response: %v", rerr)
        return rel, false
    }
    defer delete(data)

    if jerr := json.unmarshal(data, &rel); jerr != nil {
        fmt.eprintfln("olt update: cannot parse the API response: %v", jerr)
        return rel, false
    }
    if rel.tag_name == "" {
        fmt.eprintln("olt update: the API response has no tag_name")
        return rel, false
    }
    return rel, true
}

// _update_parse_version reads a dotted numeric version, ignoring a leading 'v' and any
// pre-release or build suffix.
@(private)
_update_parse_version :: proc(raw: string) -> (ver: Update_Version, ok: bool) {
    v := raw
    if strings.has_prefix(v, "v") { v = v[1:] }
    if i := strings.index_any(v, "-+"); i >= 0 { v = v[:i] }

    parts := strings.split(v, ".")
    defer delete(parts)
    if len(parts) == 0 || len(parts) > 3 { return ver, false }

    nums: [3]int
    for part, i in parts {
        n, valid := strconv.parse_int(part, 10)
        if !valid || n < 0 { return ver, false }
        nums[i] = n
    }
    return Update_Version{nums[0], nums[1], nums[2]}, true
}

@(private)
_update_compare_version :: proc(a, b: Update_Version) -> int {
    if a.major != b.major { return a.major < b.major ? -1 : 1 }
    if a.minor != b.minor { return a.minor < b.minor ? -1 : 1 }
    if a.patch != b.patch { return a.patch < b.patch ? -1 : 1 }
    return 0
}

// _update_verify_sha256 compares the file's digest with the API's "sha256:<hex>" value.
@(private)
_update_verify_sha256 :: proc(path, digest: string) -> bool {
    if !strings.has_prefix(digest, "sha256:") { return false }
    want := digest[len("sha256:"):]
    got, ok := _update_file_sha256(path)
    if !ok { return false }
    defer delete(got)
    if len(want) != len(got) { return false }
    return strings.equal_fold(want, got)
}

@(private)
_update_file_sha256 :: proc(path: string) -> (string, bool) {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil { return "", false }
    defer delete(data)

    ctx: sha2.Context_256
    sha2.init_256(&ctx)
    sha2.update(&ctx, data)
    sum: [sha2.DIGEST_SIZE_256]u8
    sha2.final(&ctx, sum[:])

    enc, eerr := hex.encode(sum[:])
    if eerr != nil { return "", false }
    defer delete(enc)
    // string(enc) does not copy, so clone before the deferred delete frees the bytes.
    return strings.clone(string(enc)), true
}

// _update_replace_binary copies src over dest. On unix the final rename is atomic; on Windows the
// running image is renamed aside first, because Windows will not overwrite a running executable.
@(private)
_update_replace_binary :: proc(src, dest: string) -> bool {
    new_path := fmt.aprintf("%s.new-%d", dest, os.get_pid())
    defer delete(new_path)

    if cerr := os.copy_file(new_path, src); cerr != nil {
        fmt.eprintfln("  cannot write %s: %v", new_path, cerr)
        return false
    }
    if cerr := os.chmod(new_path, os.Permissions_All); cerr != nil {
        fmt.eprintfln("  cannot make %s executable: %v", new_path, cerr)
        _ = os.remove(new_path)
        return false
    }

    when ODIN_OS == .Windows {
        old_path := fmt.aprintf("%s.old-%d", dest, os.get_pid())
        defer delete(old_path)

        if rerr := os.rename(dest, old_path); rerr != nil {
            fmt.eprintfln("  cannot move the running binary aside: %v", rerr)
            _ = os.remove(new_path)
            return false
        }
        if rerr := os.rename(new_path, dest); rerr != nil {
            fmt.eprintfln("  cannot install %s: %v", dest, rerr)
            _ = os.rename(old_path, dest)
            _ = os.remove(new_path)
            return false
        }
        _ = os.remove(old_path) // best effort: the running image may still be mapped

        // Windows archives hold copies of the binary, not symlinks, so update the siblings too.
        siblings := [2]string{"olt-mcp.exe", "olt-lsp.exe"}
        dir := filepath_dir(dest)
        for sibling in siblings {
            p := fmt.aprintf("%s/%s", dir, sibling)
            if os.is_file(p) { _ = os.copy_file(p, dest) }
            delete(p)
        }
    } else {
        if rerr := os.rename(new_path, dest); rerr != nil {
            fmt.eprintfln("  cannot install %s: %v", dest, rerr)
            _ = os.remove(new_path)
            return false
        }
    }
    return true
}

// _update_print_manual explains how to finish the install when the updater cannot write the target.
@(private)
_update_print_manual :: proc(url, asset_name, remote_tag, plat, dest: string) {
    tmp_dir := "/tmp"
    when ODIN_OS == .Windows { tmp_dir = "$env:TEMP" }

    fmt.eprintln("")
    fmt.eprintln("  This directory is not writable by the current user. Install it by hand:")
    when ODIN_OS == .Windows {
        fmt.eprintfln(`    curl -fL -o %s\%s %s`, tmp_dir, asset_name, url)
        fmt.eprintfln(`    tar -xf %s\%s -C %s`, tmp_dir, asset_name, tmp_dir)
        fmt.eprintfln(`    copy %s\olt-%s-%s\olt.exe %s`, tmp_dir, remote_tag, plat, dest)
    } else {
        fmt.eprintfln("    curl -fL -o %s/%s %s", tmp_dir, asset_name, url)
        fmt.eprintfln("    tar -xzf %s/%s -C %s", tmp_dir, asset_name, tmp_dir)
        fmt.eprintfln("    cp %s/olt-%s-%s/olt %s", tmp_dir, remote_tag, plat, dest)
    }
    fmt.eprintln("  Prefix the copy with sudo only if that directory needs it.")
}

// _update_run executes a command and reports a readable failure.
@(private)
_update_run :: proc(cmd: []string, what: string) -> bool {
    if len(cmd) == 0 { return false }
    state, stdout, stderr, err := os.process_exec(os.Process_Desc{command = cmd}, context.allocator)
    defer delete(stdout)
    defer delete(stderr)

    if err != nil {
        fmt.eprintfln("olt update: cannot run '%s': %v", cmd[0], err)
        if len(stderr) > 0 { fmt.eprint(string(stderr)) }
        return false
    }
    if !state.success {
        fmt.eprintfln("olt update: %s failed (exit code %d)", what, state.exit_code)
        if len(stderr) > 0 { fmt.eprint(string(stderr)) }
        return false
    }
    return true
}
