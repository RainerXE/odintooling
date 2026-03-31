#!/bin/bash

echo "Building odin-lint plugin as shared library..."

# Create artifacts directory if it doesn't exist
mkdir -p artifacts

# Build the plugin as a shared library
odin build src/integrations/ols \
    -out:artifacts/odin_lint_plugin \
    -build-mode:shared \
    -define:DEBUG=true

if [ $? -eq 0 ]; then
    echo "Plugin build successful!"
    echo "Shared library created at: artifacts/odin_lint_plugin.so (or .dll/.dylib)"
    ls -la artifacts/odin_lint_plugin*
else
    echo "Plugin build failed with exit code: $?"
    exit 1
fi