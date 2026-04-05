#!/bin/bash
# Test RuiShin using the generic Python script
echo "🔬 Testing RuiShin Project"
python3 scripts/test_generic.py /Users/rainer/Development/MyODIN/RuiShin --linter ./artifacts/odin-lint --workers 4
