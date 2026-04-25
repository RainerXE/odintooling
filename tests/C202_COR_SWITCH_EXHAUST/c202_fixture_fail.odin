package fixture_c202_fail

// ── Enum declarations ────────────────────────────────────────────────────────

Color :: enum { Red, Green, Blue }

Status :: enum { Pending, Running, Done, Failed }

// ── C202 case 1: missing one case ────────────────────────────────────────────
handle_color :: proc(c: Color) {
	switch c {
	case .Red:   _ = 1
	case .Green: _ = 2
	// missing .Blue → C202
	}
}

// ── C202 case 2: missing multiple cases ──────────────────────────────────────
handle_status :: proc(s: Status) {
	switch s {
	case .Pending: _ = 1
	// missing .Running, .Done, .Failed → C202
	}
}

// ── C202 case 3: empty switch body ───────────────────────────────────────────
handle_color_empty :: proc(c: Color) {
	switch c {
	// all cases missing → C202
	}
}
