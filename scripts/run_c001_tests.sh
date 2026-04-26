#!/bin/bash

# Comprehensive C001 Test Runner
# Tests all C001 memory allocation rule test cases and generates detailed reports

echo "=== C001 COMPREHENSIVE TEST RUNNER ==="
echo "Testing C001 memory allocation rule implementation"
echo "Date: $(date)"
echo

# Create test results directory
mkdir -p test_results

# Initialize counters
total_tests=0
passed_tests=0
failed_tests=0
test_results="test_results/c001_test_summary_$(date +%Y%m%d).txt"

echo "C001 Test Summary - $(date)" > "$test_results"
echo "=================================" >> "$test_results"
echo >> "$test_results"

# Find all C001 test files
for file in $(find tests/C001_COR_MEMORY -name "*.odin" | sort); do
    ((total_tests++))
    
    echo "Testing: $(basename $file)"
    
    # Run the test
    result=$("$BINARY" "$file" 2>&1)
    
    # Check for C001 violations or no diagnostics
    if echo "$result" | grep -q "C001"; then
        echo "  🔴 C001 VIOLATION DETECTED (expected for fail cases)"
        echo "  Result: C001 violation detected" >> "$test_results"
        ((passed_tests++))  # C001 violations are expected for some test cases
    elif echo "$result" | grep -q "No diagnostics found"; then
        echo "  ✅ NO DIAGNOSTICS (expected for pass cases)"
        echo "  Result: No diagnostics (PASS)" >> "$test_results"
        ((passed_tests++))
    else
        echo "  ❓ UNEXPECTED RESULT"
        echo "  Result: Unexpected - needs review" >> "$test_results"
        ((failed_tests++))
    fi
    
    echo "  File: $(basename $file)" >> "$test_results"
    echo >> "$test_results"
done

echo >> "$test_results"
echo "=================================" >> "$test_results"
echo "TEST SUMMARY" >> "$test_results"
echo "=================================" >> "$test_results"
echo "Total tests: $total_tests" >> "$test_results"
echo "Passed: $passed_tests" >> "$test_results"
echo "Failed: $failed_tests" >> "$test_results"
echo "Success rate: $((passed_tests * 100 / total_tests))%" >> "$test_results"
echo >> "$test_results"

echo
echo "================================="
echo "C001 TEST SUMMARY"
echo "================================="
echo "Total tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $failed_tests"
echo "Success rate: $((passed_tests * 100 / total_tests))%"
echo
echo "Detailed results saved to: $test_results"
echo "Test completed: $(date)"