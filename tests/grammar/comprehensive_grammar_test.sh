#!/bin/bash

# Comprehensive Grammar Completeness Test
# Systematically tests tree-sitter grammar against real Odin source code

echo "=== COMPREHENSIVE ODIN GRAMMAR TEST ==="
echo "Testing tree-sitter grammar completeness and correctness"
echo "Date: $(date)"
echo

# Find actual Odin source files to test
ODIN_CORE="/Users/rainer/odin/core"

# Test different categories of Odin files
declare -a test_categories=(
    "bufio:Basic I/O operations"
    "fmt:Formatting functions"
    "mem:Memory management"
    "os:Operating system functions"
    "math:Mathematical operations"
    "strconv:String conversion"
    "time:Time handling"
    "json:JSON parsing"
)

success_count=0
fail_count=0
total_tests=0

echo "🔍 DISCOVERING ODIN SOURCE FILES..."
echo

for category in "${test_categories[@]}"; do
    IFS=':' read -r dir desc <<< "$category"
    
    # Find first Odin file in this category
    file=$(find "$ODIN_CORE/$dir" -name "*.odin" -not -name "*_test.odin" | head -1)
    
    if [ -n "$file" ] && [ -f "$file" ]; then
        echo "Testing $dir category: $(basename $file)"
        echo "Description: $desc"
        
        # Test parsing - check for successful parsing message
        if ../../odin-lint "$file" 2>&1 | grep -q "Parsing successful"; then
            echo "✅ PASS: $dir/$(basename $file)"
            ((success_count++))
        else
            echo "❌ FAIL: $dir/$(basename $file)"
            ((fail_count++))
        fi
        ((total_tests++))
        echo
    else
        echo "⚠️  No files found for category: $dir"
    fi
done

echo "=== GRAMMAR COMPLETENESS ANALYSIS ==="
echo "Successful parses: $success_count"
echo "Failed parses: $fail_count"
echo "Total tests: $total_tests"
echo

# Calculate success rate
if [ $total_tests -gt 0 ]; then
    success_rate=$((success_count * 100 / total_tests))
    echo "Success rate: $success_rate%"
fi

echo
if [ $fail_count -eq 0 ] && [ $success_count -gt 0 ]; then
    echo "🎉 GRAMMAR VERIFICATION SUCCESSFUL!"
    echo "✅ Grammar appears complete and correct"
    echo "✅ All tested Odin syntax parsed successfully"
    echo "✅ Ready for rule implementation"
    exit 0
elif [ $success_count -eq 0 ]; then
    echo "❌ GRAMMAR TEST INCONCLUSIVE"
    echo "No files were successfully tested"
    exit 1
else
    echo "⚠️  GRAMMAR MAY HAVE LIMITATIONS"
    echo "Some Odin syntax could not be parsed"
    echo "Review failed cases for grammar improvements"
    exit 1
fi