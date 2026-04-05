
# Comprehensive Odin Lint Test Report

**Generated**: 2026-04-05 18:02:03
**Files Tested**: 956
**Files with Violations**: 23

## 📊 Summary

### 🔴 C001 Violations (Memory Safety)
**Total**: 0
**Files Affected**: 0

### 🟣 C002 Violations (Pointer Safety)
**Total**: 30
**Files Affected**: 23

### 🟥 Internal Errors
**Total**: 0

## 📝 Detailed Results

### 🟣 C002 Violations in: /Users/rainer/odin/core/crypto/kmac/kmac.odin

🔴 /Users/rainer/odin/core/crypto/kmac/kmac.odin:39:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/compress/shoco/shoco.odin

🔴 /Users/rainer/odin/core/compress/shoco/shoco.odin:196:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/net/url.odin

🔴 /Users/rainer/odin/core/net/url.odin:47:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/net/url.odin:51:5: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/unicode/tools/ucd/ucd.odin

🔴 /Users/rainer/odin/core/unicode/tools/ucd/ucd.odin:261:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/slice/sort.odin

🔴 /Users/rainer/odin/core/slice/sort.odin:77:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/encoding/cbor/marshal.odin

🔴 /Users/rainer/odin/core/encoding/cbor/marshal.odin:401:5: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/encoding/cbor/marshal.odin:435:5: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/encoding/cbor/marshal.odin:471:5: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/encoding/cbor/marshal.odin:548:4: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/encoding/cbor/tags.odin

🔴 /Users/rainer/odin/core/encoding/cbor/tags.odin:203:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/math/big/radix_os.odin

🔴 /Users/rainer/odin/core/math/big/radix_os.odin:67:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/image/tga/tga.odin

🔴 /Users/rainer/odin/core/image/tga/tga.odin:245:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/image/bmp/bmp.odin

🔴 /Users/rainer/odin/core/image/bmp/bmp.odin:577:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/image/bmp/bmp.odin:651:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/testing/runner.odin

🔴 /Users/rainer/odin/core/testing/runner.odin:434:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/testing/runner.odin:444:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/path.odin

🔴 /Users/rainer/odin/core/os/path.odin:743:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/path_linux.odin

🔴 /Users/rainer/odin/core/os/path_linux.odin:84:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/path_openbsd.odin

🔴 /Users/rainer/odin/core/os/path_openbsd.odin:22:3: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/path_posix.odin

🔴 /Users/rainer/odin/core/os/path_posix.odin:138:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/old/dir_unix.odin

🔴 /Users/rainer/odin/core/os/old/dir_unix.odin:15:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/old/os_linux.odin

🔴 /Users/rainer/odin/core/os/old/os_linux.odin:903:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/old/dir_windows.odin

🔴 /Users/rainer/odin/core/os/old/dir_windows.odin:87:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/os/old/stat_windows.odin

🔴 /Users/rainer/odin/core/os/old/stat_windows.odin:18:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/text/regex/compiler/debugging.odin

🔴 /Users/rainer/odin/core/text/regex/compiler/debugging.odin:35:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/text/i18n/i18n_os.odin

🔴 /Users/rainer/odin/core/text/i18n/i18n_os.odin:34:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/text/i18n/gettext.odin

🔴 /Users/rainer/odin/core/text/i18n/gettext.odin:77:40: C002 [correctness] Freeing reassigned pointer - this may free wrong memory
🔴 /Users/rainer/odin/core/text/i18n/gettext.odin:78:40: C002 [correctness] Freeing reassigned pointer - this may free wrong memory

### 🟣 C002 Violations in: /Users/rainer/odin/core/odin/parser/parser.odin

🔴 /Users/rainer/odin/core/odin/parser/parser.odin:2059:2: C002 [correctness] Freeing reassigned pointer - this may free wrong memory


## 🎯 Analysis

### ✅ Success Rate
**Clean Files**: 933 (97.6%)
**Violation Rate**: 2.4%

### 📊 Rule Effectiveness
- C001 (Memory Safety): 0 violations
- C002 (Pointer Safety): 30 violations
- Total violations: 30

## 🎉 Conclusion

Status: Production Ready 🚀
    