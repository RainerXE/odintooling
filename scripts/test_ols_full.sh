#!/bin/bash

echo "=== FULL OLS CODEBASE ANALYSIS ==="
echo "Testing C001 rule on all Odin files in vendor/ols/src/"
echo

# Initialize counters
files_with_violations=0
files_without_violations=0
total_files=0

# Test all files in the correct directory
find vendor/ols/src -name "*.odin" -type f | while read -r file; do
    ((total_files++))
    
    # Run odin-lint on the file (use absolute path)
    output=$(./odin-lint "$file" 2>&1)
    
    # Check if C001 was triggered
    if echo "$output" | grep -q "C001"; then
        ((files_with_violations++))
        echo "❌ C001 in $file"
    else
        ((files_without_violations++))
    fi
done

echo
echo "=== RESULTS ==="
echo "Total files analyzed: $total_files"
echo "Files with C001 violations: $files_with_violations"
echo "Files without violations: $files_without_violations"
echo

if [ $files_with_violations -eq 0 ]; then
    echo "🎉 EXCELLENT: No C001 violations found in OLS codebase!"
    echo "The codebase follows good memory safety practices."
else
    echo "⚠️  Found $files_with_violations files with potential memory issues"
    echo "These should be reviewed for proper defer free usage."
fi
