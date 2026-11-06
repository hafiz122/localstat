#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
zig="$PWD/.toolchain/zig-aarch64-macos-0.16.0/zig"
(cd vendor/opensas && "$zig" build test corpus programs --summary all)
swift test
python3 Tests/test_runtime.py
python3 Tests/test_fixture_runners.py
python3 scripts/procedure_parity.py check-inventory
python3 scripts/procedure_parity.py source-inventory
python3 scripts/procedure_parity.py verify-all
python3 Tests/test_procedure_parity.py
python3 Tests/test_benchmark.py
python3 Tests/test_benchmark_report.py
python3 Tests/test_benchmark_compare.py
python3 Tests/test_benchmark_compare_report.py
python3 scripts/generate-help.py --check
python3 Tests/test_help.py
python3 Tests/test_text.py
codesign --verify --deep --strict 'dist/LocalStat.app'
file 'dist/LocalStat.app/Contents/MacOS/LocalStat' 'dist/LocalStat.app/Contents/Helpers/opensas'
test "$(lipo -archs 'dist/LocalStat.app/Contents/MacOS/LocalStat')" = arm64
test "$(lipo -archs 'dist/LocalStat.app/Contents/Helpers/opensas')" = arm64
