#!/bin/bash

# Grammar Completeness Test Script
# Tests our tree-sitter grammar against real Odin source code

echo "=== ODIN GRAMMAR COMPLETENESS TEST ==="
echo "Testing tree-sitter grammar against real Odin source code"
echo

# Test files from different categories
test_files=(
    "/Users/rainer/odin/core/fmt/format.odin"      # Core formatting
    "/Users/rainer/odin/core/os/os.odin"            # OS functions
    "/Users/rainer/odin/core/mem/mem.odin"          # Memory management
    "/Users/rainer/odin/core/math/math.odin"        # Math functions
    "/Users/rainer/odin/core/strconv/strconv.odin"  # String conversion
)

success_count=0
fail_count=0

for file in "${test_files[@]}"; do
    if [ -f "$file" ]; then
        echo "🔍 Testing: $file"
        
        # Test parsing with our CLI
        if ./odin-lint "$file" > /dev/null 2>&1; then
            echo "✅ PASS: Successfully parsed $(basename $file)"
            ((success_count++))
        else
            echo "❌ FAIL: Could not parse $(basename $file)"
            ((fail_count++))
        fi
        echo
    else
        echo "⚠️  SKIP: $file not found"
    fi
done

echo "=== GRAMMAR COMPLETENESS RESULTS ==="
echo "Successful parses: $success_count"
echo "Failed parses: $fail_count"
echo "Total tests: $((success_count + fail_count))"
echo

if [ $fail_count -eq 0 ]; then
    echo "🎉 GRAMMAR APPEARS COMPLETE!"
    echo "All tested Odin source files parsed successfully."
else
    echo "⚠️  GRAMMAR MAY HAVE GAPS"
    echo "Some Odin source files could not be parsed."
fi
