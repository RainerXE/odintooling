package fixture_c203_fail

// Fake types to keep fixture self-contained
DbHandle  :: distinct int
FileHandle :: distinct int

open_db   :: proc() -> (DbHandle, bool)    { return 1, true }
close_db  :: proc(h: DbHandle)             {}
open_file :: proc(path: string) -> (FileHandle, bool) { return 2, true }
close_file :: proc(h: FileHandle)          {}

// ── C203 case 1: direct member assignment ─────────────────────────────────────
// defer close_db(db) fires when the inner if block exits.
// ctx.db is then a dangling handle.
AppCtx :: struct {
	db:   DbHandle,
	file: FileHandle,
}

test_member_assignment :: proc() {
	ctx: AppCtx
	db, ok := open_db()
	if ok {
		defer close_db(db)   // C203 — fires here, ctx.db becomes dangling
		ctx.db = db
	}
	// ctx.db is dangling here — close_db already ran
	_ = ctx
}

// ── C203 case 2: nested if block ─────────────────────────────────────────────
test_nested_if :: proc() {
	ctx: AppCtx
	if true {
		f, ok := open_file("test.txt")
		if ok {
			defer close_file(f)   // C203 — fires at end of inner if
			ctx.file = f
		}
	}
	_ = ctx
}

// ── C203 case 3: the exact pattern from the real bug ─────────────────────────
TypeResolveCtx :: struct {
	conn: DbHandle,
}

type_resolve_ctx_bug :: proc() -> TypeResolveCtx {
	type_ctx: TypeResolveCtx
	if true {
		db, db_ok := open_db()
		if db_ok {
			defer close_db(db)    // C203 — fires at inner if exit
			type_ctx.conn = db    // type_ctx.conn becomes dangling pointer
		}
	}
	return type_ctx
}
