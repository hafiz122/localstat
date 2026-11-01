#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  printf 'Release builds require a clean Git working tree.\n' >&2
  git status --short >&2
  exit 1
fi
version=$(tr -d '[:space:]' < VERSION)
if [[ "$version" != *-alpha* ]]; then
  printf 'VERSION must identify an alpha release; found %s\n' "$version" >&2
  exit 1
fi
./scripts/test.sh
LOCALSTAT_USE_TESTED_APP=1 ./scripts/package-alpha.sh
./scripts/record-candidate.sh
