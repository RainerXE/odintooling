#!/bin/bash

# ❌ UNFINISHED - OLS integration is corrupt/unfinished
echo "Building odin-lint and OLS..."

# Build odin-lint
echo "Building odin-lint..."
./scripts/build.sh

if [ $? -ne 0 ]; then
    echo "odin-lint build failed!"
    exit 1
fi

# Build OLS
echo "Building OLS..."
./scripts/build_ols_standalone.sh

if [ $? -ne 0 ]; then
    echo "OLS build failed!"
    exit 1
fi

echo "✅ All builds successful!"
echo "Artifacts:"
echo "  - artifacts/odin-lint (standalone linter)"
echo "  - artifacts/ols (language server with plugin support)"

echo ""
echo "Next steps:"
echo "1. Test OLS integration: ./artifacts/ols"
echo "2. Test odin-lint CLI: ./artifacts/odin-lint"
echo "3. Test editor integration with OLS"