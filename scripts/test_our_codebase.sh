#!/bin/bash

echo "=== TESTING C001 RULE ON OUR CODEBASE ==="
echo "Analyzing Odin files for allocation patterns"
echo

# Find all Odin source files in our project
find src/core -name "*.odin" -type f | while read -r file; do
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

echo "=== ANALYSIS COMPLETE ==="
