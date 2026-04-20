package test_c017

// C017 PASS fixture — all package-level vars are camelCase, no violations expected

// camelCase globals — OK
globalCounter  := 0
severityStrings := "info"
myGlobalPlayer := false
defaultConfig  := "prod"

// Single-char — exempt
n := 0

// _ prefix — exempt
_privateGlobal := 42

// Constants (:: declarations) are not checked by C017
MAX_SIZE :: 1000
DefaultName :: "odin-lint"
