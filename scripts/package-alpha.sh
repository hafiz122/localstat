#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
version=$(tr -d '[:space:]' < VERSION)
if [[ "$version" != *-alpha* ]]; then
  printf 'VERSION must identify an alpha release; found %s\n' "$version" >&2
  exit 1
fi

if [[ "${LOCALSTAT_USE_TESTED_APP:-0}" != 1 ]]; then
    ./scripts/build.sh
fi

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
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Contents/Info.plist")" = "${version%%-*}"
test "$(/usr/libexec/PlistBuddy -c 'Print :LocalStatReleaseVersion' "$candidate/Contents/Info.plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :LocalStatSourceCommit' "$candidate/Contents/Info.plist")" = "$(git rev-parse HEAD)"
[[ "$(file "$candidate/Contents/MacOS/LocalStat")" == *arm64* ]]
[[ "$(file "$candidate/Contents/Helpers/opensas")" == *arm64* ]]
[[ "$("$candidate/Contents/Helpers/opensas" --version)" == localstat-"$version"+* ]]
for resource in LocalStat-LICENSE.txt OpenSAS-LICENSE.txt NOTICE.txt ASSET_LICENSES.md THIRD_PARTY_NOTICES.md COMPATIBILITY.md runtime-version.txt UPSTREAM_COMMIT LocalStat.icns localstat-logo.png; do
    test -s "$candidate/Contents/Resources/$resource"
done
test -s "$candidate/Contents/Resources/Help/contents.json"
test -s "$candidate/Contents/Resources/Help/reference.html"
for notice in ReadStat-MIT.txt haven-MIT.txt pandas-LICENSE.txt; do
    cmp "licenses/$notice" "$candidate/Contents/Resources/licenses/$notice"
done
test "$(find "$release_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 2

printf 'Packaged %s\n' "$archive"
printf 'Checksum %s\n' "$checksum"
