#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=0.16.0
archive="zig-aarch64-macos-$version.tar.xz"
sha=b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489
zig="$PWD/.toolchain/zig-aarch64-macos-$version/zig"
if [[ -x "$zig" ]] && [[ "$("$zig" version)" == "$version" ]]; then
    exit 0
fi
[[ "$(uname -sm)" == 'Darwin arm64' ]] || { echo 'This build targets Apple Silicon macOS.' >&2; exit 1; }
mkdir -p .toolchain
# The official community mirror uses the same release bytes; verify the pinned digest.
if ! curl -fL --retry 2 --connect-timeout 15 --max-time 300 "https://ziglang.freetls.fastly.net/$archive" -o ".toolchain/$archive"; then
    curl -fL --retry 2 "https://ziglang.org/download/$version/$archive" -o ".toolchain/$archive"
fi
printf '%s  %s\n' "$sha" ".toolchain/$archive" | shasum -a 256 -c -
tar -xf ".toolchain/$archive" -C .toolchain
