package test_c016

// C016 FAIL fixture — local vars with uppercase, violations expected

bad_proc :: proc() {
    playerCount := 0          // VIOLATION: camelCase
    PlayerPtr   := &playerCount  // VIOLATION: PascalCase
    TotalScore  := 100        // VIOLATION: PascalCase
    isValid     := true       // VIOLATION: camelCase
    filePath    := "test.odin" // VIOLATION: camelCase
    MaxItems    := 64         // VIOLATION: PascalCase

    _ = PlayerPtr
    _ = TotalScore
    _ = isValid
    _ = filePath
    _ = MaxItems
    _ = playerCount
}
