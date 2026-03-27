#!/bin/bash

echo "Building odin-lint..."

# Build the main application
odin build src/core -out:artifacts/odin-lint -define:DEBUG=true

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Executable: artifacts/odin-lint"
else
    echo "Build failed!"
    exit 1
fi