// C002 All Tests - Comprehensive test suite for pointer safety rule
// This file documents all C002 test cases and their expected behavior

package c002_all

import "core:fmt"

// C002 Test Suite Organization
// ============================
//
// Test files follow the naming convention: c002_description.odin
// Each file tests specific aspects of the C002 pointer safety rule
//
// Categories:
// - Basic functionality tests
// - Edge cases and special patterns
// - Fixture tests (pass/fail validation)

// Basic Functionality Tests
// -------------------------
// c002_fixture_fail.odin - Wrong pointer free (should fail)
// c002_fixture_pass.odin - Proper pointer free (should pass)

// Fixture Tests (Traditional pass/fail)
// -------------------------------------
// c002_fixture_fail.odin - Should trigger C002 violation
// c002_fixture_pass.odin - Should pass (0 violations)

// Test Execution
// --------------
// To run all C002 tests:
//   ./odin-lint tests/C002_COR_POINTER/*.odin
//
// Expected Results:
// - c002_fixture_fail.odin: Should trigger C002 violation
// - c002_fixture_pass.odin: Should pass (0 violations)

main :: proc() {
    fmt.println("C002 Test Suite")
    fmt.println("===============")
    fmt.println("Rule: Defer free on wrong pointer")
    fmt.println("Category: CORRECTNESS")
    fmt.println("Test files: c002_fixture_fail.odin, c002_fixture_pass.odin")
}