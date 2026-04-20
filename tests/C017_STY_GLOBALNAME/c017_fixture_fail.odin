package test_c017

// C017 FAIL fixture — package-level vars that violate camelCase

// snake_case globals — VIOLATION
severity_strings := "info"       // VIOLATION: underscore
global_counter   := 0            // VIOLATION: underscore
default_config   := "prod"       // VIOLATION: underscore

// PascalCase globals — VIOLATION
GlobalCounter  := 0              // VIOLATION: starts uppercase
SeverityLevel  := 2              // VIOLATION: starts uppercase
