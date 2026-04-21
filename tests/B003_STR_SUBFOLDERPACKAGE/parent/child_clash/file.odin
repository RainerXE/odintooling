package graphics

// B003 FAIL — same package name "graphics" as parent directory
// Odin treats this as a SEPARATE package that must be explicitly imported.
// This is almost certainly a mistake.
helper :: proc() {}
