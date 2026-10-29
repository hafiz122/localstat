#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
version=$(tr -d '[:space:]' < VERSION)
if [[ "$version" != *-alpha* ]]; then
  printf 'VERSION must identify an alpha release; found %s\n' "$version" >&2
  exit 1
fi

./scripts/build.sh

release_dir="$root/dist/release"
archive="$release_dir/LocalStat-$version-arm64.zip"
checksum="$archive.sha256"
rm -rf "$release_dir"
mkdir -p "$release_dir"
ditto -c -k --sequesterRsrc --keepParent "$root/dist/LocalStat.app" "$archive"
(cd "$release_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")")
(cd "$release_dir" && shasum -a 256 -c "$(basename "$checksum")")

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
ditto -x -k "$archive" "$scratch"
candidate="$scratch/LocalStat.app"
codesign --verify --deep --strict "$candidate"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Contents/Info.plist")" = "0.1.0"
[[ "$(file "$candidate/Contents/MacOS/LocalStat")" == *arm64* ]]
[[ "$(file "$candidate/Contents/Helpers/opensas")" == *arm64* ]]
[[ "$("$candidate/Contents/Helpers/opensas" --version)" == localstat-"$version"+* ]]

printf 'Packaged %s\n' "$archive"
printf 'Checksum %s\n' "$checksum"
