package fixture_c202_pass

// ── Enum declarations ────────────────────────────────────────────────────────

Color :: enum { Red, Green, Blue }

Status :: enum { Pending, Running, Done, Failed }

// ── PASS: exhaustive switch covering all cases ────────────────────────────────
handle_color_full :: proc(c: Color) {
	switch c {
	case .Red:   _ = 1
	case .Green: _ = 2
	case .Blue:  _ = 3
	}
}

// ── PASS: wildcard case covers all remaining ──────────────────────────────────
handle_color_wildcard :: proc(c: Color) {
	switch c {
	case .Red: _ = 1
	case _:    _ = 0  // wildcard — OK
	}
}

// ── PASS: #partial switch — explicit opt-out ──────────────────────────────────
handle_partial :: proc(s: Status) {
	#partial switch s {
	case .Pending: _ = 1
	// intentionally incomplete — #partial suppresses C202
	}
}

// ── PASS: non-enum switch (integer) — not flagged ────────────────────────────
handle_int :: proc(n: int) {
	switch n {
	case 1: _ = 1
	case 2: _ = 2
	}
}
