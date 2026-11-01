// codegraph_sync.odin — the CodeGraph-facing entry points.
//
// olt's graph database already IS a CodeGraph database (see graph_schema.odin), so
// there is nothing to translate: --codegraph-init and --codegraph-sync run the
// ordinary export with the database placed where CodeGraph looks for it,
// .codegraph/codegraph.db. That lets a project whose CodeGraph does not index
// Odin yet use CodeGraph's tools on Odin code.
//
// Choose one writer per project: once your CodeGraph indexes Odin itself, let it
// own codegraph.db and keep olt's own graph at .codegraph/olt.db.
package core

import "core:fmt"
import "core:os"

CODEGRAPH_DB_PATH :: ".codegraph/codegraph.db"

// codegraph_reset removes a database and its WAL files so the next export is a full rebuild.
codegraph_reset :: proc(db_path: string) {
    _ = os.remove(db_path)
    _ = os.remove(fmt.tprintf("%s-wal", db_path))
    _ = os.remove(fmt.tprintf("%s-shm", db_path))
}

// codegraph_write_gitignore writes .codegraph/.gitignore if it does not already exist.
// Matches the file CodeGraph itself would create, so *.db files are not committed.
codegraph_write_gitignore :: proc(db_path: string) {
    dir := filepath_dir(db_path)
    if dir == "" || dir == "." { dir = ".codegraph" }
    gi_path := fmt.tprintf("%s/.gitignore", dir)
    if os.is_file(gi_path) { return }
    content := "# CodeGraph data files — local to each machine, do not commit\n*.db\n*.db-wal\n*.db-shm\ncache/\n*.log\n.dirty\n"
    _ = os.write_entire_file(gi_path, transmute([]u8)string(content))
}
