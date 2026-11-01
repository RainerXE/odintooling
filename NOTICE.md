# Third-party notices

olt itself is licensed under the zlib-style licence in `LICENSE`. The parts below are not
olt's code: they keep their own licences, which are all permissive and compatible with it,
and which require their notices to travel with them. **Ship this file with every source or
binary distribution of olt.**

## Included in the source tree

- **CodeGraph database schema** — `ffi/codegraph/schema.sql`, copied unmodified from
  [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) (`src/db/schema.sql`).
  MIT License, Copyright (c) 2026 Colby McHenry. Full text: `ffi/codegraph/LICENSE.codegraph`.
- **tree-sitter API headers** — `ffi/tree_sitter/tree-sitter-api.h`, `ffi/tree_sitter/tree_sitter.h`,
  `ffi/tree_sitter/bindings/api.h`, from [tree-sitter](https://github.com/tree-sitter/tree-sitter).
  MIT License, Copyright (c) 2014 Max Brunsfeld.
- **SQLite binding** — the git submodule `vendor/odin-sqlite3`
  ([RainerXE/odin-sqlite](https://github.com/RainerXE/odin-sqlite), zlib-style licence). Its declarations were
  originally adapted from [saenai255/odin-sqlite3](https://github.com/saenai255/odin-sqlite3), MIT License,
  Copyright 2025 Paul Cosma; its own `THIRD_PARTY_NOTICES.md` carries that notice and the SQLite one, and
  travels with it.

## Built or linked into the olt binary

- **tree-sitter** (git submodule `ffi/tree_sitter/tree-sitter-lib`) — MIT License, Copyright (c) 2014 Max Brunsfeld.
- **tree-sitter-odin** (git submodule `ffi/tree_sitter/tree-sitter-odin`, tag `v1.3.0`) — MIT License,
  Copyright (c) 2023 Amaan Qureshi.
- **SQLite** (the amalgamation inside `vendor/odin-sqlite3`) — in the public domain.
- **The Odin standard library** (`core:`, `base:`, `vendor:`), compiled statically into the binary —
  BSD 3-Clause License, Copyright (c) 2016-2026 Ginger Bill. Its licence requires that binary
  distributions reproduce the copyright notice and conditions in the accompanying documentation or
  materials: this file, plus the licence text in the Odin distribution (`LICENSE` in the Odin repository),
  satisfies that.
