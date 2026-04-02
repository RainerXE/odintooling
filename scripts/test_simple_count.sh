#!/bin/bash

# Simple violation counter
# Counts C001 violations across all Odin libraries

echo "🔍 Counting C001 violations in all Odin libraries..."

ODIN_ROOT="/Users/rainer/odin"
total=0

# Test core libraries
for file in $(find "$ODIN_ROOT/core" -name "*.odin" 2>/dev/null); do
    output=$(./artifacts/odin-lint "$file" 2>&1)
    count=$(echo "$output" | grep -c "C001" || echo "0")
    if [ "$count" -gt 0 ]; then
        echo "🔴 $file: $count violation(s)"
        total=$((total + count))
    fi
done

echo ""
echo "📊 Total C001 violations in core: $total"
