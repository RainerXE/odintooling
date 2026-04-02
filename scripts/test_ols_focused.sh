#!/bin/bash

echo "=== FOCUSED OLS CODEBASE ANALYSIS ==="
echo "Testing C001 rule on Odin files in vendor/ols/src/"
echo "Generated: $(date)"
echo

# Configuration
LINT_BINARY="./artifacts/odin-lint"
OUTPUT_FILE="ols_focused_analysis_$(date +%Y%m%d).txt"
DETAILED_REPORT="ols_focused_detailed_$(date +%Y%m%d).txt"

# Initialize counters
files_with_violations=0
files_without_violations=0
total_files=0
violation_count=0
internal_error_count=0

# Initialize output files
echo "=== Focused OLS Codebase Analysis Report ===" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Linter: odin-lint" >> "$OUTPUT_FILE"
echo "Rule: C001 (Allocation without defer free)" >> "$OUTPUT_FILE"
echo "Directory: vendor/ols/src/" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Test OLS source code
echo "🔍 Testing OLS source code..."

# Find all Odin files in vendor/ols/src
while IFS= read -r file; do
    ((total_files++))
    
    # Run odin-lint on the file
    output=$($LINT_BINARY "$file" 2>&1)
    
    # Check for C001 violations
    if echo "$output" | grep -q "C001"; then
        ((files_with_violations++))
        
        # Count individual violations
        violation_count=$((violation_count + $(echo "$output" | grep -c "C001")))
        
        echo "❌ C001 violations in: $file"
        echo "$file" >> "$OUTPUT_FILE"
        echo "$output" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Also write to detailed report
        echo "=== FILE: $file ===" >> "$DETAILED_REPORT"
        echo "$output" >> "$DETAILED_REPORT"
        echo "" >> "$DETAILED_REPORT"
    else
        ((files_without_violations++))
        echo "✅ $file - No violations"
    fi
    
    # Check for internal errors
    if echo "$output" | grep -q "INTERNAL ERROR"; then
        ((internal_error_count++))
        echo "🟣 INTERNAL ERROR in: $file"
    fi
    
done < <(find "vendor/ols/src" -name "*.odin" -type f)

echo
if [ $total_files -eq 0 ]; then
    echo "⚠️  No Odin files found in vendor/ols/src/"
    echo "⚠️  No Odin files found in vendor/ols/src/" >> "$OUTPUT_FILE"
else
    echo "=== FINAL RESULTS ==="
    echo "📊 Total files analyzed: $total_files"
    echo "🔴 Files with C001 violations: $files_with_violations"
    echo "✅ Files without violations: $files_without_violations"
    echo "🟣 Internal errors: $internal_error_count"
    echo "📝 Total C001 violations found: $violation_count"
    echo

    # Add summary to output file
    echo "=== SUMMARY ===" >> "$OUTPUT_FILE"
    echo "Total files analyzed: $total_files" >> "$OUTPUT_FILE"
    echo "Files with C001 violations: $files_with_violations" >> "$OUTPUT_FILE"
    echo "Files without violations: $files_without_violations" >> "$OUTPUT_FILE"
    echo "Internal errors: $internal_error_count" >> "$OUTPUT_FILE"
    echo "Total C001 violations found: $violation_count" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Final assessment
    if [ $files_with_violations -eq 0 ]; then
        echo "🎉 EXCELLENT: No C001 violations found in OLS codebase!"
        echo "The codebase follows good memory safety practices."
        echo "🎉 EXCELLENT: No C001 violations found in OLS codebase!" >> "$OUTPUT_FILE"
    else
        echo "⚠️  Found $files_with_violations files with potential memory issues"
        echo "📋 Detailed violations saved to: $DETAILED_REPORT"
        echo "⚠️  Found $files_with_violations files with potential memory issues" >> "$OUTPUT_FILE"
    fi
fi

echo "📄 Summary report saved to: $OUTPUT_FILE"
if [ $files_with_violations -gt 0 ]; then
    echo "📝 Detailed violations saved to: $DETAILED_REPORT"
fi
echo "🎯 Analysis completed at: $(date)"