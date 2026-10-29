#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bootstrap-zig.sh
root="$PWD"
zig="$root/.toolchain/zig-aarch64-macos-0.16.0/zig"
revision=$(cut -c1-12 vendor/opensas/UPSTREAM_COMMIT)
release_version=$(tr -d '[:space:]' < "$root/VERSION")
bundle_version=${LOCALSTAT_BUNDLE_VERSION:-0.1.0}
build_number=${LOCALSTAT_BUILD_NUMBER:-1}
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  printf 'Invalid release version in VERSION: %s\n' "$release_version" >&2
  exit 1
fi
if [[ ! "$bundle_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
  printf 'Invalid bundle version (%s) or build number (%s)\n' "$bundle_version" "$build_number" >&2
  exit 1
fi
(cd vendor/opensas && "$zig" build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos -Dversion="localstat-$release_version+$revision")
swift build -c release --arch arm64
app="$root/dist/LocalStat.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources/Examples"
cp .build/arm64-apple-macosx/release/LocalStat "$app/Contents/MacOS/LocalStat"
cp vendor/opensas/zig-out/bin/opensas "$app/Contents/Helpers/opensas"
cp assets/LocalStat.icns "$app/Contents/Resources/LocalStat.icns"
cp assets/localstat-logo.png "$app/Contents/Resources/localstat-logo.png"
cp examples/*.sas "$app/Contents/Resources/Examples/"
cp docs/COMPATIBILITY.md "$app/Contents/Resources/COMPATIBILITY.md"
cp LICENSE "$app/Contents/Resources/LocalStat-LICENSE.txt"
cp NOTICE "$app/Contents/Resources/NOTICE.txt"
cp vendor/opensas/LICENSE "$app/Contents/Resources/OpenSAS-LICENSE.txt"
cp vendor/opensas/UPSTREAM_COMMIT "$app/Contents/Resources/UPSTREAM_COMMIT"
"$app/Contents/Helpers/opensas" --version > "$app/Contents/Resources/runtime-version.txt"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalStat</string>
<key>CFBundleIdentifier</key><string>io.github.hafiz122.localstat</string>
<key>CFBundleName</key><string>LocalStat</string>
<key>CFBundleDisplayName</key><string>LocalStat</string>
<key>CFBundleIconFile</key><string>LocalStat.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDocumentTypes</key>
<array><dict>
<key>CFBundleTypeName</key><string>SAS Program</string>
<key>CFBundleTypeExtensions</key><array><string>sas</string></array>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>LSHandlerRank</key><string>Owner</string>
</dict></array>
<key>CFBundleShortVersionString</key><string>$bundle_version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Helpers/opensas"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
