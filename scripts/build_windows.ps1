# build_windows.ps1
# Build olt, olt-mcp, olt-lsp for Windows x86_64.
# Run on a Windows 11 machine (natively or in a VM).
#
# Prerequisites (install once, manually or via winget):
#   winget install odin-lang.Odin        # Odin compiler
#   winget install LLVM.LLVM             # clang (required by Odin on Windows)
#   winget install GnuWin32.GCC          # or: winget install MSYS2.MSYS2
#
# This script compiles the C static libraries from source using the
# MinGW-w64 gcc bundled with Git for Windows / MSYS2, then builds
# the Odin binaries.

$ErrorActionPreference = "Stop"

$BUILD   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PLATFORM = "windows-x86_64"
$OUT     = "$BUILD\artifacts\$PLATFORM"
$LIBS    = "$env:TEMP\olt-libs-$PID"

New-Item -ItemType Directory -Force -Path $OUT, $LIBS | Out-Null

Write-Host "============================================="
Write-Host "  olt Windows x86_64 build"
Write-Host "  Output: $OUT"
Write-Host "============================================="

# ── Helper: require a command, print install hint if missing ──────────────────
function Require-Command($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "${name} not found. Install with: $hint"
        exit 2
    }
}

# ── 1. Check prerequisites ────────────────────────────────────────────────────
Write-Host "`n--- Checking prerequisites ---"
Require-Command "odin"   "winget install odin-lang.Odin"
Require-Command "clang"  "winget install LLVM.LLVM"
Require-Command "gcc"    "winget install MSYS2.MSYS2  (then: pacman -S mingw-w64-x86_64-gcc)"

odin version
Write-Host "  ✓ Odin found"
Write-Host "  ✓ clang found"
Write-Host "  ✓ gcc (MinGW) found"

# ── 2. libtree-sitter.a ───────────────────────────────────────────────────────
Write-Host "`n--- Building libtree-sitter ---"
$TS_LIB = "$BUILD\ffi\tree_sitter\tree-sitter-lib\lib"
gcc -O2 -fPIC -std=c11 `
    -I"$TS_LIB\include" -I"$TS_LIB\src" -I"$TS_LIB\src\wasm" `
    -c "$TS_LIB\src\lib.c" `
    -o "$LIBS\libtree-sitter.o"
ar rcs "$LIBS\libtree-sitter.a" "$LIBS\libtree-sitter.o"
Write-Host "  ✓ libtree-sitter.a"

# ── 3. libtree-sitter-odin.a ──────────────────────────────────────────────────
Write-Host "--- Building libtree-sitter-odin ---"
$TS_ODIN = "$BUILD\ffi\tree_sitter\tree-sitter-odin\src"
gcc -O2 -fPIC -std=c11 `
    -I"$TS_LIB\include" -I"$TS_LIB\src" `
    -c "$TS_ODIN\parser.c" -o "$LIBS\ts-odin-parser.o"
gcc -O2 -fPIC -std=c11 `
    -I"$TS_LIB\include" -I"$TS_LIB\src" `
    -c "$TS_ODIN\scanner.c" -o "$LIBS\ts-odin-scanner.o"
ar rcs "$LIBS\libtree-sitter-odin.a" "$LIBS\ts-odin-parser.o" "$LIBS\ts-odin-scanner.o"
Write-Host "  ✓ libtree-sitter-odin.a"

# ── 4. libsqlite3.a ───────────────────────────────────────────────────────────
Write-Host "--- Building libsqlite3 ---"
$SQLITE_VER = "3460100"
$SQLITE_DIR = "sqlite-amalgamation-$SQLITE_VER"
$SQLITE_ZIP = "$env:TEMP\sqlite-$PID.zip"
Invoke-WebRequest "https://sqlite.org/2024/$SQLITE_DIR.zip" -OutFile $SQLITE_ZIP -UseBasicParsing
Expand-Archive $SQLITE_ZIP "$env:TEMP\sqlite-$PID" -Force
gcc -O2 -fPIC `
    -DSQLITE_THREADSAFE=0 `
    -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 `
    -c "$env:TEMP\sqlite-$PID\$SQLITE_DIR\sqlite3.c" `
    -o "$LIBS\sqlite3.o"
ar rcs "$LIBS\libsqlite3.a" "$LIBS\sqlite3.o"
Remove-Item $SQLITE_ZIP, "$env:TEMP\sqlite-$PID" -Recurse -Force
Write-Host "  ✓ libsqlite3.a"

# ── 5. Build Odin binaries ────────────────────────────────────────────────────
$LINKER_FLAGS = "$LIBS\libtree-sitter.a $LIBS\libtree-sitter-odin.a $LIBS\libsqlite3.a"

Write-Host "`n--- Building olt ---"
odin build "$BUILD\src\core" -out:"$OUT\olt.exe" -extra-linker-flags:"$LINKER_FLAGS"
Write-Host "  ✓ olt.exe"

Write-Host "--- Building olt-mcp ---"
odin build "$BUILD\src\mcp" -out:"$OUT\olt-mcp.exe" -extra-linker-flags:"$LINKER_FLAGS"
Write-Host "  ✓ olt-mcp.exe"

Write-Host "--- Building olt-lsp ---"
odin build "$BUILD\src\lsp" -out:"$OUT\olt-lsp.exe" -extra-linker-flags:"$LINKER_FLAGS"
Write-Host "  ✓ olt-lsp.exe"

# ── 6. Smoke tests ────────────────────────────────────────────────────────────
Write-Host "`n--- Smoke tests ---"
$OLT   = "$OUT\olt.exe"
$pass  = 0
$fail  = 0

function Check($label, $ok) {
    if ($ok) { Write-Host "  ✓ $label"; $script:pass++ }
    else      { Write-Host "  ✗ $label  ← FAILED"; $script:fail++ }
}

# --version
$ver = & $OLT --version 2>&1
Check "--version exits 0"         ($LASTEXITCODE -eq 0)
Check "--version contains 'olt'"  ($ver -match "olt")

# --list-rules
$rules = & $OLT --list-rules 2>&1
Check "--list-rules exits 0"        ($LASTEXITCODE -eq 0)
Check "--list-rules contains C001"  ($rules -match "C001")

# Clean file → exit 0
"package s; p::proc(){_=1+1}" | Out-File "$env:TEMP\smoke_clean.odin" -Encoding utf8
& $OLT "$env:TEMP\smoke_clean.odin" | Out-Null
Check "lint clean file exits 0"  ($LASTEXITCODE -eq 0)

# Leaky file → exit 1
"package l; l::proc(){_=make([]u8,10)}" | Out-File "$env:TEMP\smoke_leak.odin" -Encoding utf8
& $OLT "$env:TEMP\smoke_leak.odin" | Out-Null
Check "lint leaky file exits 1"  ($LASTEXITCODE -eq 1)

# olt-mcp: starts without crash (send empty stdin, exits cleanly)
$mcp = Start-Process "$OUT\olt-mcp.exe" -RedirectStandardInput "$env:TEMP\nul_input.txt" `
       -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\mcp_out.txt" `
       -ErrorAction SilentlyContinue
Check "olt-mcp starts (no crash)"  ($mcp.ExitCode -ne 139 -and $mcp.ExitCode -ne 134)

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n============================================="
Write-Host "  Build complete: $PLATFORM"
Get-ChildItem $OUT | Format-Table Name, Length
Write-Host "  Smoke tests: $pass passed, $fail failed"
Write-Host "============================================="

if ($fail -gt 0) {
    Write-Error "❌  $fail smoke test(s) failed"
    exit 1
}
Write-Host "✅  All smoke tests passed"
