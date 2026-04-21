package graphics_utils

// B003 PASS — distinct package name from parent "graphics"
clamp :: proc(v, lo, hi: f32) -> f32 { return min(max(v, lo), hi) }
