#!/bin/bash
# Test OLS using the generic Python script
echo "🔬 Testing OLS Project"
python3 scripts/test_generic.py /Users/rainer/Development/MyODIN/odintooling/vendor/ols --linter ./artifacts/odin-lint --workers 4
