#!/bin/bash

# Test odin-lint on Odin core libraries
# Usage: ./scripts/test_odin_core_libraries.sh [output_file]
# If output_file is provided, results will be appended to it

set -e

# Configuration
ODIN_CORE_DIR="/Users/rainer/odin/core"
LINT_BINARY="./artifacts/odin-lint"
OUTPUT_FILE="odin_core_test_results_$(date +%Y%m%d).txt"
MAX_FILES=50  # Limit to avoid overwhelming output

# Use custom output file if provided
if [ $# -ge 1 ]; then
    OUTPUT_FILE=$1
fi

echo "🔍 Testing odin-lint on Odin core libraries"
echo "📁 Core directory: $ODIN_CORE_DIR"
echo "📄 Output file: $OUTPUT_FILE"
echo "📊 Starting at: $(date)"
echo ""

# Initialize output file
echo "=== Odin Core Library Test Results ===" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Linter version: $(./artifacts/odin-lint --version 2>/dev/null || echo 'unknown')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Find all Odin files
file_count=0
violation_count=0
internal_error_count=0

while IFS= read -r file; do
    # Skip test files and examples
    if [[ "$file" == *"test"* ]] || [[ "$file" == *"example"* ]] || [[ "$file" == *"_test"* ]]; then
        continue
    fi
    
    file_count=$((file_count + 1))
    
    if [ $file_count -gt $MAX_FILES ]; then
        break
    fi
    
    echo "[$file_count] Testing: $file"
    
    # Run the linter and capture output
    output=$($LINT_BINARY "$file" 2>&1)
    
    # Check for violations
    if echo "$output" | grep -q "C001"; then
        violation_count=$((violation_count + 1))
        echo "$file" >> "$OUTPUT_FILE"
        echo "$output" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Check for internal errors
    if echo "$output" | grep -q "INTERNAL ERROR"; then
        internal_error_count=$((internal_error_count + 1))
        echo "🟣 INTERNAL ERROR in: $file" >> "$OUTPUT_FILE"
        echo "$output" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Check for no diagnostics (success)
    if echo "$output" | grep -q "No diagnostics found"; then
        echo "✅ $file - No violations found"
    fi
    
done < <(find "$ODIN_CORE_DIR" -name "*.odin" -type f)

echo ""
echo "📊 Test Summary:"
echo "📄 Files tested: $file_count (limited to $MAX_FILES)"
echo "🔴 Violations found: $violation_count"
echo "🟣 Internal errors: $internal_error_count"
echo ""
echo "📄 Full results saved to: $OUTPUT_FILE"
echo "🎯 Test completed at: $(date)"
