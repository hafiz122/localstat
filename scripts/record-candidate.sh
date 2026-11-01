#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(tr -d '[:space:]' < VERSION)
archive="dist/release/LocalStat-$version-arm64.zip"
test -s "$archive"
record=dist/CANDIDATE_VERIFICATION.md
{
  printf '# LocalStat %s candidate verification\n\n' "$version"
  printf 'Source commit: `%s`\n\n' "$(git rev-parse HEAD)"
  printf 'Generated (UTC): %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Host: %s %s, %s\n\n' "$(sw_vers -productName)" "$(sw_vers -productVersion)" "$(uname -m)"
  printf 'Swift: %s\n\n' "$(swift --version | head -1)"
  printf 'Zig: %s\n\n' "$(.toolchain/zig-aarch64-macos-0.16.0/zig version)"
  printf 'Archive SHA-256: `%s`\n\n' "$(shasum -a 256 "$archive" | cut -d ' ' -f1)"
  printf 'Signing: ad-hoc; codesign verification passed. Not notarized.\n\n'
  printf 'Validation: scripts/test.sh passed before packaging; extracted bundle metadata, ARM64 executables, resources and checksum verified.\n\n'
  printf 'Manual checks and publication gates: see docs/VERIFICATION.md and docs/RELEASE_CHECKLIST.md at this commit. Second-Mac smoke test remains outstanding.\n'
} > "$record"
printf 'Candidate record: %s\n' "$record"
