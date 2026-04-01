#!/bin/bash

# Simple test script
echo "Testing Odin core libraries..."

# Test the specific file we know has a violation
./artifacts/odin-lint /Users/rainer/odin/core/bufio/scanner.odin 2>&1 | grep "C001"

echo "Test completed"
