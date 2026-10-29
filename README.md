# LocalStat

<img src="assets/localstat-logo.png" alt="LocalStat logo" width="180">

A native AppKit editor that runs a local ARM64 SAS-language interpreter. The runtime is an extended, pinned copy of [OpenSAS](https://github.com/kirha-ai/opensas), not SAS Institute's engine.

## Build and run

Requires an Apple Silicon Mac, macOS 14 or newer, Xcode with its command-line tools selected, and network access for the first compiler download. The build pins Zig 0.16.0 and verifies the release SHA-256. Swift is supplied by Xcode. Once built, the app runs offline without a developer toolchain.

```sh
./scripts/build.sh
open 'dist/LocalStat.app'
```

The app is ad-hoc signed for local use. It is not notarized or prepared for public distribution. Both executables are ARM64; there is no VM, translation service, Python backend, or hosted SAS dependency.

## Use

On first launch, example programs are copied to `~/Library/Application Support/LocalStat/Examples`. Open a project folder to choose the working directory used for relative file paths and `%INCLUDE`. Double-click a `.sas` file in the sidebar or use File > Open Program. File > New Program creates another editor tab.

- Command-S saves; Shift-Command-S saves as another file.
- Command-F opens the native find bar; normal Mac editing/undo shortcuts work.
- Command-R runs the **entire current editor buffer**, including unsaved changes.
- Command-period stops the current run, escalating to SIGKILL after two seconds if required.
- Double-click an original-source diagnostic to navigate. Navigation is disabled if its editor buffer has changed, or if the position belongs to macro-expanded text.
- File > Export Last Run saves complete raw output and diagnostics.
- Help > Compatibility and Limitations opens the supported-subset document in a native read-only window.

Every run starts a fresh process: WORK datasets and macro definitions do not persist between submissions. Files explicitly written by your program persist. Output is buffered by OpenSAS until the run finishes, so cancellation may lose that buffered output. Output and diagnostics are kept in memory; very large results require corresponding memory.

## First modeling feature

```sas
proc reg data=measurements;
  model y = x;
run;
quit;
```

The local extension provides a bounded ordinary-least-squares PROC REG with numeric predictors, an intercept, complete-case filtering, and text estimates/ANOVA. It uses scaled Householder QR with column pivoting. Unsupported procedure options fail visibly. See [the compatibility matrix](docs/COMPATIBILITY.md) for exclusions and numerical edge cases.

## Verify

```sh
./scripts/test.sh
```

This builds the app, runs OpenSAS unit/conformance/end-to-end suites, Swift process integration tests, and packaged-runtime regression checks. Python 3 is only used by the tests, never by the app or runtime. Published example checks have source citations in the test. They are not a claim of new validation against an installed SAS engine.

## Source layout

- `Sources/LocalStat`: AppKit editor, document tabs, project list and result views.
- `Sources/SASCore`: subprocess runner and diagnostic coordinate parsing.
- `vendor/opensas`: source snapshot with local changes; `UPSTREAM_COMMIT` records provenance.
- `Tests`: numerical/CLI and Swift integration checks.
- `scripts`: compiler bootstrap, app packaging and verification.

[Runtime changes](docs/RUNTIME_CHANGES.md) distinguish our modifications from upstream. The upstream Apache-2.0 license is retained and bundled with the app. SAS is a trademark of SAS Institute Inc.; this project is independent and unaffiliated.
