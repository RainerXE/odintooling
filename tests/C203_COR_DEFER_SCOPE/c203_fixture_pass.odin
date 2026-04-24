package fixture_c203_pass

// Fake types to keep fixture self-contained
DbHandle :: distinct int

open_db  :: proc() -> (DbHandle, bool) { return 1, true }
close_db :: proc(h: DbHandle)          {}

AppCtx :: struct {
	db: DbHandle,
}

// ── PASS: defer in procedure body (not inner block) ──────────────────────────
// Odin defer at procedure scope fires at procedure exit — always correct.
test_proc_body_defer :: proc() {
	ctx: AppCtx
	db, ok := open_db()
	defer close_db(db)   // OK — fires at proc exit, ctx.db valid throughout
	if ok {
		ctx.db = db
	}
	_ = ctx
}

// ── PASS: defer in inner block, no outer-scope assignment ────────────────────
// defer fires when inner block exits, but nothing from outside uses the handle.
test_no_outer_assignment :: proc() {
	if true {
		db, ok := open_db()
		if ok {
			defer close_db(db)   // OK — db not assigned to any outer variable
			_ = db
		}
	}
}

// ── PASS: outer var assigned before inner block (no defer+member in same block) ─
// ctx.db = db happens in the outer block; defer is NOT in the same block as ctx.db = db.
test_outer_block_assignment :: proc() {
	ctx: AppCtx
	db, ok := open_db()
	if ok {
		ctx.db = db   // assignment in outer block
		if true {
			defer close_db(db)   // inner block, but assignment is NOT a sibling here
		}
	}
	_ = ctx
}

// ── PASS: local-only usage in inner block ────────────────────────────────────
// local_handle = db is a plain local assignment (no '.') — not flagged.
test_local_only :: proc() {
	local_handle := DbHandle(0)
	if true {
		db, ok := open_db()
		if ok {
			defer close_db(db)
			local_handle = db   // plain local assignment, no member access
		}
	}
	_ = local_handle
}
