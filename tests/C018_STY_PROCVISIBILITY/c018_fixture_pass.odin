package test_c018

// C018 PASS fixture — proc names match visibility convention

// Public procs — PascalCase (API surface)
SetShaderValue :: proc() {}
InitRenderer   :: proc() {}
ParseFile      :: proc() -> int { return 0 }
GetPlayer      :: proc() -> int { return 0 }

// Private procs — snake_case (internal)
@(private)
init_internal :: proc() {}

@(private="file")
compute_hash :: proc(data: []u8) -> u32 { return 0 }

@(private)
add_player_ptr :: proc() {}
