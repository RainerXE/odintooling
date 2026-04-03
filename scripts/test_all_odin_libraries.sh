#!/bin/bash

# Comprehensive Odin Library Test - Bash Wrapper
# Now uses Python script for better reliability and performance

echo "🔬 Comprehensive Odin Library Test"
echo "===================================="
echo ""
echo "Using Python implementation for better performance..."
echo ""

# Run the Python script
python3 "${0%.sh}.py" "$@"
