#!/bin/bash

echo "=== TESTING C001 RULE ON OLS CODEBASE ==="
echo "Analyzing external Odin project for allocation patterns"
echo

# Count total files
total_files=$(find vendor/ols -name "*.odin" -type f | wc -l)
echo "Found $total_files Odin files in OLS codebase"
echo

# Test a sample of files (first 10 to avoid too much output)
find vendor/ols -name "*.odin" -type f | head -10 | while read -r file; do
    echo "🔍 Testing: $file"
    
    # Run odin-lint on the file
    output=$(../odin-lint "$file" 2>&1)
    
    # Check if C001 was triggered
    if echo "$output" | grep -q "C001"; then
        echo "❌ C001 VIOLATION found in $file"
        echo "$output" | grep "C001"
    else
        echo "✅ No C001 violations in $file"
    fi
    echo
done

echo "=== PARTIAL ANALYSIS COMPLETE ==="
echo "Tested 10 files from OLS codebase"
echo "Run full test to analyze all $total_files files"
