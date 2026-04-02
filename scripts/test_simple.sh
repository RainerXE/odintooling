#!/bin/bash

# Simple test script
# Configuration
OUTPUT_DIR="test_results"
OUTPUT_FILE="$OUTPUT_DIR/simple_test_$(date +%Y%m%d).txt"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Testing Odin core libraries..."

# Test the specific file we know has a violation
# Save output to file
./artifacts/odin-lint /Users/rainer/odin/core/bufio/scanner.odin 2>&1 | tee "$OUTPUT_FILE"

echo "Test completed"
echo "📄 Results saved to: $OUTPUT_FILE"
