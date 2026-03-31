#!/bin/bash

# ❌ UNFINISHED - OLS integration is corrupt/unfinished
echo "Building OLS with odin-lint plugin support..."

# Build OLS from vendor directory
cd vendor/ols || { echo "Failed to enter OLS directory"; exit 1; }

# Build OLS binary
./build.sh

if [ $? -eq 0 ]; then
    echo "OLS build successful!"
    echo "Binary: vendor/ols/ols"
    
    # Copy to artifacts for easy access
    cp ols ../../artifacts/ols
    echo "Copied to: artifacts/ols"
else
    echo "OLS build failed!"
    exit 1
fi