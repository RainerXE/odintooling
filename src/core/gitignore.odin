// gitignore.odin — honour .gitignore when scanning a project.
//
// Git is the authority on its own ignore rules (nested .gitignore files, negation,
// .git/info/exclude, the user's global excludes), so olt asks it instead of
// re-implementing them: `git ls-files --exclude-standard -i` lists the ignored files.
// Two lists are needed, because a file git tracks can still match an ignore pattern
// (odin-http tracks examples/minimal/main.odin and ignores a folder called "minimal");
// CodeGraph skips such files, and so does olt:
//   -c -i   tracked files that match an ignore pattern
//   -o -i   untracked files that match an ignore pattern
//
// Outside a git repository, or without git, nothing is filtered. Files named
// explicitly on the command line are never filtered: asking for a file is not scanning.
package core

import "core:fmt"
import "core:os"
import "core:strings"

// git_ignored_files returns the .odin files at or below dir that git ignores, as paths
// relative to dir (git prints paths relative to the directory it is run in). ok is false
// when dir is not in a git repository, or git cannot be run.
git_ignored_files :: proc(dir: string, allocator := context.temp_allocator) -> (ignored: map[string]struct{}, ok: bool) {
    ignored = make(map[string]struct{}, allocator)
    for flags in ([][2]string{{"-c", "-i"}, {"-o", "-i"}}) {
        args := make([dynamic]string, context.temp_allocator)
        append(&args, "git", "-C", dir, "ls-files", "-z", "--exclude-standard", flags[0], flags[1], "--", "*.odin")
        state, stdout, _, err := os.process_exec(os.Process_Desc{command = args[:]}, context.temp_allocator)
        if err != nil || !state.success || state.exit_code != 0 {
            delete(ignored)
            return {}, false
        }
        for rel in strings.split(string(stdout), "\x00", context.temp_allocator) {
            if rel != "" { ignored[strings.clone(rel, allocator)] = {} }
        }
    }
    return ignored, true
}

// filter_gitignored removes from files[from:] every file git ignores under target.
// The removed strings are freed.
filter_gitignored :: proc(files: ^[dynamic]string, from: int, target: string) {
    ignored, ok := git_ignored_files(target)
    if !ok || len(ignored) == 0 { return }

    base := fmt.tprintf("%s/", _abs_path(target))
    kept := from
    for i in from..<len(files) {
        abs := _abs_path(files[i])
        rel := abs[len(base):] if strings.has_prefix(abs, base) else abs
        if rel in ignored {
            delete(files[i])
            continue
        }
        files[kept] = files[i]
        kept += 1
    }
    resize(files, kept)
}
