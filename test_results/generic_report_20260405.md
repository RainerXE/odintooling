
# Comprehensive Odin Lint Test Report

**Generated**: 2026-04-05 18:03:29
**Files Tested**: 126
**Files with Violations**: 4

## 📊 Summary

### 🔴 C001 Violations (Memory Safety)
**Total**: 0
**Files Affected**: 0

### 🟣 C002 Violations (Pointer Safety)
**Total**: 20
**Files Affected**: 4

### 🟥 Internal Errors
**Total**: 0

## 📝 Detailed Results

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/main.odin

🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/main.odin:100:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/main.odin:137:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin

🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:200:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:207:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:940:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:1134:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:1261:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:1299:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:2209:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/demo.odin:2220:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin

🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:200:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:211:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:974:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:1173:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:1318:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:1360:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:2342:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/tools/odinfmt/tests/random/.snapshots/demo.odin:2358:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/Development/MyODIN/odintooling/vendor/ols/src/server/requests.odin

🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/src/server/requests.odin:260:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/Development/MyODIN/odintooling/vendor/ols/src/server/requests.odin:478:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory


## 🎯 Analysis

### ✅ Success Rate
**Clean Files**: 122 (96.8%)
**Violation Rate**: 3.2%

### 📊 Rule Effectiveness
- C001 (Memory Safety): 0 violations
- C002 (Pointer Safety): 20 violations
- Total violations: 20

## 🎉 Conclusion

Status: Production Ready 🚀
    