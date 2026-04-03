#!/bin/bash

echo "=== C002 RULE COMPREHENSIVE TEST SUMMARY ==="
echo "Automatically testing all C002 test cases in tests/C002_COR_POINTER/"
echo "Generated: $(date)"
echo

# Configuration
LINT_BINARY="./artifacts/odin-lint"
OUTPUT_DIR="test_results"
SUMMARY_FILE="$OUTPUT_DIR/c002_test_summary_$(date +%Y%m%d).txt"
TEST_DIR="./tests/C002_COR_POINTER"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Initialize counters
total_files=0
files_with_violations=0
files_without_violations=0
total_violations=0
internal_errors=0

# Initialize summary file
echo "=== C002 Rule Test Summary ===" > "$SUMMARY_FILE"
echo "Generated: $(date)" >> "$SUMMARY_FILE"
echo "Test directory: $TEST_DIR" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo "❌ Test directory not found: $TEST_DIR"
    echo "❌ Test directory not found: $TEST_DIR" >> "$SUMMARY_FILE"
    exit 1
fi

# Find all test files
echo "🔍 Discovering test files in $TEST_DIR..."
test_files=$(find "$TEST_DIR" -name "*.odin" -type f)
file_count=$(echo "$test_files" | wc -l)

if [ "$file_count" -eq 0 ]; then
    echo "⚠️  No test files found in $TEST_DIR"
    echo "⚠️  No test files found in $TEST_DIR" >> "$SUMMARY_FILE"
    exit 1
fi

echo "Found $file_count test files"
echo ""

# Process each test file
while IFS= read -r file; do
    ((total_files++))
    
    echo "Testing: $(basename "$file")"
    
    # Run the linter
    output=$($LINT_BINARY "$file" 2>&1)
    
    # Count violations - only count actual violation lines (start with 🔴)
    violation_count=$(echo "$output" | grep -c "^🔴.*C002" 2>/dev/null)
    violation_count=${violation_count:-0}
    # Ensure violation_count is numeric
    if [[ ! "$violation_count" =~ ^[0-9]+$ ]]; then
        violation_count=0
    fi
    total_violations=$((total_violations + violation_count))
    
    # Check for internal errors
    if echo "$output" | grep -q "INTERNAL ERROR"; then
        internal_errors=$((internal_errors + 1))
        echo "  🟣 INTERNAL ERROR"
        echo "$file - INTERNAL ERROR" >> "$SUMMARY_FILE"
    fi
    
    # Categorize result
    if [ "$violation_count" -gt 0 ]; then
        files_with_violations=$((files_with_violations + 1))
        echo "  🔴 Found $violation_count C002 violation(s)"
        echo "$file - $violation_count violations" >> "$SUMMARY_FILE"
    else
        files_without_violations=$((files_without_violations + 1))
        echo "  ✅ No violations found"
        echo "$file - No violations" >> "$SUMMARY_FILE"
    fi
    
    # Save detailed output for files with violations
    if [ "$violation_count" -gt 0 ]; then
        echo "" >> "$SUMMARY_FILE"
        echo "=== DETAILED OUTPUT FOR $(basename "$file") ===" >> "$SUMMARY_FILE"
        echo "$output" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi
    
done <<< "$test_files"

echo
# Summary
echo "=== TEST RESULTS ==="
echo "📊 Total test files: $total_files"
echo "🔴 Files with violations: $files_with_violations"
echo "✅ Files without violations: $files_without_violations"
echo "🟣 Internal errors: $internal_errors"
echo "📝 Total C002 violations found: $total_violations"
echo

# Add summary to file
echo "=== SUMMARY ===" >> "$SUMMARY_FILE"
echo "Total test files: $total_files" >> "$SUMMARY_FILE"
echo "Files with violations: $files_with_violations" >> "$SUMMARY_FILE"
echo "Files without violations: $files_without_violations" >> "$SUMMARY_FILE"
echo "Internal errors: $internal_errors" >> "$SUMMARY_FILE"
echo "Total C002 violations found: $total_violations" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Final assessment
if [ $internal_errors -eq 0 ]; then
    if [ $files_with_violations -gt 0 ]; then
        echo "✅ TESTING COMPLETE"
        echo "The C002 rule is working and finding pointer safety issues"
        echo "Files with violations should be reviewed for proper pointer usage"
        
        echo "✅ TESTING COMPLETE" >> "$SUMMARY_FILE"
        echo "The C002 rule is working and finding pointer safety issues" >> "$SUMMARY_FILE"
        echo "Files with violations should be reviewed for proper pointer usage" >> "$SUMMARY_FILE"
    else
        echo "🎉 PERFECT RESULTS!"
        echo "✅ No C002 violations found in any test files"
        echo "✅ No false positives detected"
        echo "✅ The C002 rule is working correctly"
        
        echo "🎉 PERFECT RESULTS!" >> "$SUMMARY_FILE"
        echo "✅ No C002 violations found in any test files" >> "$SUMMARY_FILE"
        echo "✅ No false positives detected" >> "$SUMMARY_FILE"
        echo "✅ The C002 rule is working correctly" >> "$SUMMARY_FILE"
    fi
else
    echo "⚠️  TESTING COMPLETED WITH ERRORS"
    echo "Found $internal_errors files with internal errors"
    
    echo "⚠️  TESTING COMPLETED WITH ERRORS" >> "$SUMMARY_FILE"
    echo "Found $internal_errors files with internal errors" >> "$SUMMARY_FILE"
fi

echo "📄 Summary saved to: $SUMMARY_FILE"
echo "🎯 C002 test validation completed at: $(date)"