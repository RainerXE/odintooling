package test_c018

// C018 FAIL fixture — proc names do NOT match visibility convention

// Public procs with snake_case — VIOLATION (should be PascalCase)
set_shader_value :: proc() {}      // VIOLATION: public, must be PascalCase
init_renderer    :: proc() {}      // VIOLATION: public, must be PascalCase
parse_file       :: proc() -> int { return 0 }  // VIOLATION

// Private procs with PascalCase — VIOLATION (should be snake_case)
@(private)
InitInternal :: proc() {}          // VIOLATION: private, must be snake_case

@(private="file")
ComputeHash :: proc(data: []u8) -> u32 { return 0 }  // VIOLATION
