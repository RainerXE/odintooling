#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"

# Configuration
OUTPUT_DIR="test_results/our_codebase"
REPORT_FILE="$OUTPUT_DIR/our_codebase_analysis_$(date +%Y%m%d).txt"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=== TESTING C001 RULE ON OUR CODEBASE ==="
echo "Analyzing Odin files for allocation patterns"
echo

# Initialize report
echo "=== C001 Analysis Report - Our Codebase ===" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Statistics
files_with_violations=0
files_without_violations=0
total_violations=0

# Find all Odin source files in our project
find src/core -name "*.odin" -type f | while read -r file; do
    echo "🔍 Testing: $file"
    
    # Run odin-lint on the file
    output=$("$OLT_BINARY" "$file" 2>&1)
    
    # Check if C001 was triggered
    if echo "$output" | grep -q "C001"; then
        echo "❌ C001 VIOLATION found in $file"
        echo "$file" >> "$REPORT_FILE"
        echo "$output" | grep "C001" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Count violations
        violation_count=$(echo "$output" | grep -c "^🔴.*C001" 2>/dev/null || echo "0")
        total_violations=$((total_violations + violation_count))
        files_with_violations=$((files_with_violations + 1))
    else
        echo "✅ No C001 violations in $file"
        files_without_violations=$((files_without_violations + 1))
    fi
    echo
done

# Generate summary
echo "" >> "$REPORT_FILE"
echo "=== SUMMARY ===" >> "$REPORT_FILE"
echo "Files analyzed: $((files_with_violations + files_without_violations))" >> "$REPORT_FILE"
echo "Files with violations: $files_with_violations" >> "$REPORT_FILE"
echo "Files without violations: $files_without_violations" >> "$REPORT_FILE"
echo "Total C001 violations: $total_violations" >> "$REPORT_FILE"

echo "=== ANALYSIS COMPLETE ==="
echo "📄 Report saved to: $REPORT_FILE"
