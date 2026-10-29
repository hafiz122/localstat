#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bootstrap-zig.sh
root="$PWD"
zig="$root/.toolchain/zig-aarch64-macos-0.16.0/zig"
revision=$(cut -c1-12 vendor/opensas/UPSTREAM_COMMIT)
(cd vendor/opensas && "$zig" build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos -Dversion="localstat-0.1+$revision")
swift build -c release --arch arm64
app="$root/dist/LocalStat.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources/Examples"
cp .build/arm64-apple-macosx/release/LocalStat "$app/Contents/MacOS/LocalStat"
cp vendor/opensas/zig-out/bin/opensas "$app/Contents/Helpers/opensas"
cp assets/LocalStat.icns "$app/Contents/Resources/LocalStat.icns"
cp assets/localstat-logo.png "$app/Contents/Resources/localstat-logo.png"
cp examples/*.sas "$app/Contents/Resources/Examples/"
cp docs/COMPATIBILITY.md "$app/Contents/Resources/COMPATIBILITY.md"
cp vendor/opensas/LICENSE "$app/Contents/Resources/OpenSAS-LICENSE.txt"
cp vendor/opensas/UPSTREAM_COMMIT "$app/Contents/Resources/UPSTREAM_COMMIT"
"$app/Contents/Helpers/opensas" --version > "$app/Contents/Resources/runtime-version.txt"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalStat</string>
<key>CFBundleIdentifier</key><string>io.github.hafiz122.localstat</string>
<key>CFBundleName</key><string>LocalStat</string>
<key>CFBundleDisplayName</key><string>LocalStat</string>
<key>CFBundleIconFile</key><string>LocalStat.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Helpers/opensas"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
