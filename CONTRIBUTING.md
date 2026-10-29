# Contributing to LocalStat

LocalStat is an early macOS and language-runtime project. Small, tested changes
are easiest to review.

## Development setup

Use an Apple Silicon Mac with macOS 14 or later and Xcode command-line tools.
The first build downloads the pinned Zig 0.16.0 archive and verifies its
SHA-256 checksum.

```sh
./scripts/test.sh
```

That command builds the app, runs the vendored runtime suites, runs Swift
integration tests, runs packaged-runtime checks, and verifies the bundle.

## Pull requests

- Keep unrelated changes separate.
- Add tests for behavior changes and unsupported syntax.
- Update `docs/COMPATIBILITY.md` for changes to language coverage.
- Do not call a feature SAS-verified without reference output produced by an
  installed SAS engine and a documented comparison method.
- Preserve the pinned upstream commit and Apache-2.0 notices. Document changes
  to vendored OpenSAS code in `docs/RUNTIME_CHANGES.md`.
- Do not commit generated build directories, logs, release archives, secrets,
  private data, or proprietary SAS materials.

By submitting a contribution, you agree that it may be distributed under this
repository's Apache-2.0 license.
