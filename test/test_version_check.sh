#!/bin/bash

echo "Testing OLS Version Detection"
echo "================================"
echo ""

# Test with current Odin version
cd vendor/ols

# Try to start OLS (it will detect version and exit if incompatible)
echo "Starting OLS with current Odin version..."
echo ""

# Create a simple test that triggers the version check
# We'll use a timeout to prevent hanging
timeout 2s ./ols 2>&1 || true

echo ""
echo "Version detection complete!"

# Show what version was detected
./ols version 2>&1 | head -1