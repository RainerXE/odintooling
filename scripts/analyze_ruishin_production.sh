#!/bin/bash

echo "🔬 Analyzing RuiShin Production Code (excluding tests)"
echo "===================================================="

# Define source directory
SOURCE_DIR="/Users/rainer/Development/MyODIN/RuiShin/src"

# Count total files
echo "📊 Counting production files..."
TOTAL_FILES=$(find "$SOURCE_DIR" -name "*.odin" | wc -l | tr -d ' ')
echo "📁 Total production files: $TOTAL_FILES"

# Run odin-lint on source directory only
echo "🔍 Running odin-lint on production code..."
cd /Users/rainer/SynologyDrive/Development/MyODIN/odintooling

# Create output directory
mkdir -p test_results/ruishin_production

# Run analysis on all Odin files in source directory
find "$SOURCE_DIR" -name "*.odin" -exec ./artifacts/odin-lint {} \; > "test_results/ruishin_production/production_analysis_$(date +%Y%m%d).md" 2>&1

echo "✅ Analysis complete!"
echo "📄 Report saved to: test_results/ruishin_production/production_analysis_$(date +%Y%m%d).md"

# Extract key metrics
echo ""
echo "📊 Key Metrics:"
echo "============="

# Count C001 violations
C001_COUNT=$(grep -c "C001" "test_results/ruishin_production/production_analysis_$(date +%Y%m%d).md" || echo "0")
echo "🔴 C001 violations: $C001_COUNT"

# Count C002 violations  
C002_COUNT=$(grep -c "C002" "test_results/ruishin_production/production_analysis_$(date +%Y%m%d).md" || echo "0")
echo "🟣 C002 violations: $C002_COUNT"

# Calculate clean rate
if [ "$TOTAL_FILES" -gt "0" ]; then
    VIOLATION_FILES=$(grep -c "🔴\|🟣" "test_results/ruishin_production/production_analysis_$(date +%Y%m%d).md" || echo "0")
    CLEAN_FILES=$((TOTAL_FILES - VIOLATION_FILES))
    CLEAN_PERCENT=$((CLEAN_FILES * 100 / TOTAL_FILES))
    echo "✅ Clean files: $CLEAN_FILES ($CLEAN_PERCENT%)"
else
    echo "✅ Clean files: 0 (0%)"
fi

echo ""
echo "🎯 Production Code Quality Summary"
echo "==================================="
echo "Total production files analyzed: $TOTAL_FILES"
echo "Memory safety issues (C001): $C001_COUNT"
echo "Pointer safety issues (C002): $C002_COUNT"
echo "Total critical issues: $((C001_COUNT + C002_COUNT))"

if [ "$C002_COUNT" -gt "0" ]; then
    echo ""
    echo "⚠️  CRITICAL: $C002_COUNT pointer safety issues found!"
    echo "These should be prioritized for immediate fixing."
fi