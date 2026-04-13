package test_naming

// C003: procedures starting with uppercase — should be flagged
InitParser :: proc() {}          // VIOLATION: PascalCase proc
ParseFile :: proc() -> int { return 0 }  // VIOLATION: PascalCase proc
MyHelper :: proc(x: int) {}      // VIOLATION: PascalCase proc

// C003: procedures starting with lowercase — should be clean
init_parser :: proc() {}
parseFile :: proc() -> int { return 0 }
my_helper :: proc(x: int) {}

// C007: type names starting with lowercase — should be flagged
myStruct :: struct { x: int }    // VIOLATION: lowercase type
tokenKind :: enum { A, B, C }    // VIOLATION: lowercase enum

// C007: type names starting with uppercase — should be clean
MyStruct :: struct { x: int }
TokenKind :: enum { A, B, C }
