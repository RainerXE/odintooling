package core

// =============================================================================
// C007: Type names must use PascalCase
// =============================================================================
//
// Struct, enum, and union names should start with an uppercase letter.
// Detection is performed by naming_scm_run in c003-STY-Naming.odin.
//
// Category: STYLE
// =============================================================================

c007_rule :: proc() -> Rule {
    return Rule{
        id       = "C007",
        tier     = "style",
        category = .STYLE,
        matcher  = nil,  // logic lives in naming_scm_run (c003-STY-Naming.odin)
        message  = c007_message,
        fix_hint = c007_fix_hint,
    }
}

c007_message :: proc() -> string {
    return "Type name should start with uppercase (PascalCase)"
}

c007_fix_hint :: proc() -> string {
    return "Rename: e.g. 'myStruct' → 'MyStruct'"
}
