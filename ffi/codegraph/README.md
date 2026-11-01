# ffi/codegraph — CodeGraph's database schema, vendored

`schema.sql` is [CodeGraph](https://github.com/colbymchenry/codegraph)'s SQLite
schema (`src/db/schema.sql`), copied unmodified. olt's graph database uses it
as its core, so a database written by olt is a database CodeGraph can open.
CodeGraph is MIT licensed, copyright (c) 2026 Colby McHenry; its licence text
is in `LICENSE.codegraph`.

| | |
| --- | --- |
| source | colbymchenry/codegraph `src/db/schema.sql` |
| upstream commit | `cc86361` (package version 1.6.2) |
| `CURRENT_SCHEMA_VERSION` | 16 |

Rules for keeping it right:

- **Never edit `schema.sql`.** Refresh it with `scripts/update_codegraph_schema.sh`,
  which also updates `CODEGRAPH_SCHEMA_VERSION` in `src/core/graph_schema.odin`.
- `schema.sql` already contains every migration's result. A fresh database is
  `schema.sql` plus a `schema_versions` row for the *current* version
  (described "Initial schema includes all migrations"), exactly what CodeGraph
  does itself. Writing a lower version makes CodeGraph re-run migrations over
  columns that already exist and fail with `duplicate column name`.
- olt-only data lives in separate `odin_*` tables that CodeGraph never touches.
- `scripts/test_codegraph_contract.sh` opens an olt database with a real
  CodeGraph build and checks that it works; run it after every refresh.
