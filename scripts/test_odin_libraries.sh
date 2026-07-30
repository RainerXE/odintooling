#!/bin/bash
# Test Odin Core Libraries using the generic Python script
echo "🔬 Testing Odin Core Libraries"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_platform.sh"
python3 "$SCRIPT_DIR/test_generic.py" /Users/rainer/odin/core --linter "$OLT_BINARY" --workers 8
