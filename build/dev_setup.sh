#!/bin/bash

echo "Setting up development environment for odin-lint + OLS integration..."

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Create symlinks for easy access
ln -sf ../vendor/ols/ols artifacts/ols 2>/dev/null || true

# Set up builtin directory for OLS
if [ ! -d "vendor/ols/builtin" ]; then
    echo "⚠️  OLS builtin directory missing!"
    echo "Please ensure OLS is properly set up with builtin files"
fi

echo "Development environment ready!"
echo ""
echo "Available commands:"
echo "  ./scripts/build.sh          - Build odin-lint only"
echo "  ./scripts/build_ols.sh      - Build OLS only"
echo "  ./scripts/build_all.sh      - Build both odin-lint and OLS"
echo ""
echo "Testing:"
echo "  ./artifacts/odin-lint       - Test standalone linter"
echo "  ./artifacts/ols             - Test OLS with plugin support"
echo ""
echo "Editor integration:"
echo "  Set OLS path to: $(pwd)/artifacts/ols"
echo "  Ensure builtin directory is accessible to OLS"