#!/bin/bash
# Test Odin Core Libraries using the generic Python script
echo "🔬 Testing Odin Core Libraries"
python3 scripts/test_generic.py /Users/rainer/odin/core --linter ./artifacts/odin-lint --workers 8
