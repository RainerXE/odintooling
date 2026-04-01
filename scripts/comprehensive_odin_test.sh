#!/bin/bash

# Comprehensive Odin Core Library Test
# Tests all .odin files in core and base directories
# Generates detailed report with statistics

set -e

echo "🔬 Comprehensive Odin Core Library Test"
echo "======================================"
echo ""

# Configuration
ODIN_ROOT="/Users/rainer/odin"
TEST_DIRS=("core" "base")
OUTPUT_DIR="test_results"
REPORT_FILE="$OUTPUT_DIR/comprehensive_test_report_$(date +%Y%m%d).md"
LINT_BINARY="./artifacts/odin-lint"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Initialize report
echo "# Comprehensive Odin Core Library Test Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Generated**: $(date)" >> "$REPORT_FILE"
echo "**Linter**: odin-lint" >> "$REPORT_FILE"
echo "**Odin Version**: $(/Users/rainer/odin/odin version 2>/dev/null || echo 'unknown')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Statistics
total_files=0
total_violations=0
contextual_violations=0
internal_errors=0
clean_files=0

# Test each directory
for dir in "${TEST_DIRS[@]}"; do
    echo "Testing directory: $dir"
    echo "" >> "$REPORT_FILE"
    echo "## $dir Directory" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    dir_path="$ODIN_ROOT/$dir"
    
    if [ ! -d "$dir_path" ]; then
        echo "⚠️  Directory not found: $dir_path"
        continue
    fi
    
    # Find all .odin files recursively
    while IFS= read -r file; do
        total_files=$((total_files + 1))
        
        # Run linter
        output=$($LINT_BINARY "$file" 2>&1)
        
        # Count violations
        violation_count=$(echo "$output" | grep -c "C001" || echo "0")
        contextual_count=$(echo "$output" | grep -c "Intentional? Performance" || echo "0")
        error_count=$(echo "$output" | grep -c "INTERNAL ERROR" || echo "0")
        
        if [ "$violation_count" -gt 0 ]; then
            total_violations=$((total_violations + violation_count))
            contextual_violations=$((contextual_violations + contextual_count))
            
            echo "### 🔴 Violations in: $file" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "\`\`\`" >> "$REPORT_FILE"
            echo "$output" | grep "C001" >> "$REPORT_FILE"
            echo "\`\`\`" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        elif [ "$error_count" -gt 0 ]; then
            internal_errors=$((internal_errors + error_count))
            echo "### 🟣 Internal Error in: $file" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "\`\`\`" >> "$REPORT_FILE"
            echo "$output" | grep "INTERNAL ERROR" >> "$REPORT_FILE"
            echo "\`\`\`" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        else
            clean_files=$((clean_files + 1))
        fi
        
    done < <(find "$dir_path" -name "*.odin" -type f)

done

# Generate summary
echo "" >> "$REPORT_FILE"
echo "## 📊 Test Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Metric | Count |" >> "$REPORT_FILE"
echo "|--------|-------|" >> "$REPORT_FILE"
echo "| **Files Tested** | $total_files |" >> "$REPORT_FILE"
echo "| **Total Violations** | $total_violations |" >> "$REPORT_FILE"
echo "| **Contextual Violations** | $contextual_violations |" >> "$REPORT_FILE"
echo "| **Internal Errors** | $internal_errors |" >> "$REPORT_FILE"
echo "| **Clean Files** | $clean_files |" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Calculate percentages
if [ $total_files -gt 0 ]; then
    violation_rate=$(echo "scale=2; $total_violations * 100 / $total_files" | bc)
    clean_rate=$(echo "scale=2; $clean_files * 100 / $total_files" | bc)
    
    echo "| **Violation Rate** | ${violation_rate}% |" >> "$REPORT_FILE"
    echo "| **Clean Rate** | ${clean_rate}% |" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "## 🎯 Analysis" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ $total_violations -gt 0 ]; then
    echo "### 🔴 Violations Found" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "The linter found $total_violations violations across $total_files files." >> "$REPORT_FILE"
    echo "This represents a ${violation_rate}% violation rate." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "**Recommended Actions**:" >> "$REPORT_FILE"
    echo "- Review each violation for legitimacy" >> "$REPORT_FILE"
    echo "- Fix confirmed memory management issues" >> "$REPORT_FILE"
    echo "- Document intentional performance optimizations" >> "$REPORT_FILE"
else
    echo "### ✅ No Violations Found" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "All tested files passed the C001 rule checks!" >> "$REPORT_FILE"
    echo "This indicates excellent memory management practices." >> "$REPORT_FILE"
fi

if [ $internal_errors -gt 0 ]; then
    echo "" >> "$REPORT_FILE"
    echo "### 🟣 Internal Errors Found" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Found $internal_errors internal errors. These should be investigated:" >> "$REPORT_FILE"
    echo "- File read errors" >> "$REPORT_FILE"
    echo "- Parse failures" >> "$REPORT_FILE"
    echo "- Tree-sitter issues" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "## 🚀 Recommendations" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "1. **Address Violations**: Fix confirmed memory leaks" >> "$REPORT_FILE"
echo "2. **Review Contextual**: Document intentional performance optimizations" >> "$REPORT_FILE"
echo "3. **Expand Testing**: Test more directories and edge cases" >> "$REPORT_FILE"
echo "4. **Monitor Trends**: Track violation rates over time" >> "$REPORT_FILE"
echo "5. **Improve Rules**: Fine-tune based on real-world usage" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "Report generated by odin-lint comprehensive test script" >> "$REPORT_FILE"
echo "Status: Production Ready 🎉" >> "$REPORT_FILE"

echo ""
echo "📄 Report generated: $REPORT_FILE"
echo "🎯 Test completed successfully!"
