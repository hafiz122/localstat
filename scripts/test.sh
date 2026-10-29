#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
zig="$PWD/.toolchain/zig-aarch64-macos-0.16.0/zig"
(cd vendor/opensas && "$zig" build test corpus programs --summary all)
swift test
python3 Tests/test_runtime.py
codesign --verify --deep --strict 'dist/LocalStat.app'
file 'dist/LocalStat.app/Contents/MacOS/LocalStat' 'dist/LocalStat.app/Contents/Helpers/opensas'
