// C001 All Tests - Comprehensive test suite for memory allocation rule
// This file documents all C001 test cases and their expected behavior

package c001_all

import "core:fmt"

// C001 Test Suite Organization
// ============================
//
// Test files follow the naming convention: c001_description.odin
// Each file tests specific aspects of the C001 memory allocation rule
//
// Categories:
// - Basic functionality tests
// - Edge cases and special patterns
// - Suppression and exclusion tests
// - Performance-related tests
// - Allocator detection tests

// Basic Functionality Tests
// -------------------------
// c001_basic.odin - Simple allocation test cases
// c001_simple_allocation.odin - Basic allocation without defer free
// c001_make_slice.odin - Tests make([]T) allocations
// c001_new_allocation.odin - Tests new(T) allocations
// c001_mixed_cases.odin - Mixed cases (some with defer, some without)
// c001_proper_defer.odin - Proper allocations with defer free (should pass)
// c001_missing_defer.odin - Allocations missing defer free (should fail)

// Fixture Tests (Traditional pass/fail validation)
// -----------------------------------------------
// c001_fixture_pass.odin - Should pass (0 violations)
// c001_fixture_fail.odin - Should trigger C001 violation
// c001_fixture_simple_fail.odin - Simple fail case from fixtures

// Edge Cases and Special Patterns
// -------------------------------
// c001_edge_cases.odin - Edge cases and boundary conditions
// c001_min_function.odin - Minimal function test cases
// c001_complex.odin - Complex allocation scenarios
// c001_allocation_methods.odin - Different allocation methods

// Suppression and Exclusion Tests
// ------------------------------
// c001_suppression.odin - Suppression comment functionality
// c001_exclusion.odin - Comprehensive exclusion pattern testing
// c001_allocator.odin - Allocator argument detection

// Performance-Related Tests
// -------------------------
// c001_performance.odin - Performance-critical block detection
// c001_perf.odin - Performance marker testing
// c001_perf_separate.odin - Separate performance test cases

// Allocator Detection Tests
// -------------------------
// c001_allocator_detection.odin - Allocator detection scenarios
// c001_defer_extraction.odin - Defer statement extraction tests
// c001_improvements.odin - Rule improvement test cases

// Test Execution
// --------------
// To run all C001 tests:
//   ./odin-lint tests/C001_COR_MEMORY/*.odin
//
// Expected Results:
// - Files with "proper" or "correct" in name should pass (0 violations)
// - Files with "missing", "violation", or test-specific patterns should fail
// - Suppression tests should show 0 violations when properly suppressed
// - Fixture tests maintain traditional pass/fail expectations:
//   * c001_fixture_pass.odin: 0 violations (pass)
//   * c001_fixture_fail.odin: 1+ violations (fail)
//   * c001_fixture_simple_fail.odin: 1+ violations (fail)

main :: proc() {
    fmt.println("C001 Test Suite")
    fmt.println("================")
    fmt.println("Total test files: 20+")
    fmt.println("Categories: Basic, Edge Cases, Suppression, Performance, Allocators")
    fmt.println("Run individual tests with: ./odin-lint tests/C001_COR_MEMORY/c001_*.odin")
}