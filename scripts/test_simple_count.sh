#!/bin/bash

# Simple violation counter
# Counts C001 violations across all Odin libraries

# Configuration
OUTPUT_DIR="test_results"
OUTPUT_FILE="$OUTPUT_DIR/simple_count_$(date +%Y%m%d).txt"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🔍 Counting C001 violations in all Odin libraries..."

ODIN_ROOT="/Users/rainer/odin"
total=0

# Initialize report
echo "=== C001 Violation Count Report ===" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Test core libraries
for file in $(find "$ODIN_ROOT/core" -name "*.odin" 2>/dev/null); do
    output=$(./artifacts/odin-lint "$file" 2>&1)
    count=$(echo "$output" | grep -c "^🔴.*C001" 2>/dev/null || echo "0")
    if [ "$count" -gt 0 ]; then
        echo "🔴 $file: $count violation(s)"
        echo "$file: $count violation(s)" >> "$OUTPUT_FILE"
        total=$((total + count))
    fi
done

# Generate summary
echo "" >> "$OUTPUT_FILE"
echo "📊 Total C001 violations in core: $total" >> "$OUTPUT_FILE"

echo ""
echo "📊 Total C001 violations in core: $total"
echo "📄 Report saved to: $OUTPUT_FILE"
