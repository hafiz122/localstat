# Install LocalStat 0.1.3-alpha

Requires an Apple Silicon Mac and macOS 14 or later. The alpha app contains its
runtime; Zig, Xcode, Python, and SAS are not needed to run the downloaded app.

Download `LocalStat-0.1.3-alpha-arm64.zip` and its `.zip.sha256` file from the
same [public GitHub release](https://github.com/hafiz122/localstat/releases/tag/v0.1.3-alpha).
From the directory containing both files, verify:

```sh
shasum -a 256 -c LocalStat-0.1.3-alpha-arm64.zip.sha256
```

Expect `OK`. If verification fails, discard the download and download both files
again from the same release. Extract the ZIP and move LocalStat.app into your
Applications folder.

The alpha is ad-hoc signed, without Developer ID or notarization. macOS
Gatekeeper may block a downloaded copy. Inspect and trust the source before
using macOS's available Open Anyway control in Privacy & Security. A checksum
checks download consistency; it does not establish the developer's identity.
Building from source is also supported through `scripts/build.sh`.

## First run

LocalStat copies bundled examples into Application Support/LocalStat/Examples.
Open an example and press Command-R. Open Project Folder changes the working
directory for relative file paths and `%INCLUDE`. Save works with Command-S;
Command-period stops a run. File > Export Report as PDF exports the last run.

Every run starts fresh WORK and macro state. Explicitly written files persist.
Programs run with the app's filesystem permissions and inherited environment;
use programs and project folders you trust. The app does not upload programs
or results.

## Known issues and reporting

This alpha supports a documented SAS-language subset. See COMPATIBILITY.md and
in-app Help. ODS PDF, graphics, persistent sessions, and dataset browsing are
not implemented. Output is buffered until execution finishes; stopping may
discard it. Large logs require corresponding memory. Editor indentation is a
heuristic, not a complete SAS formatter.

Use the app-bug or compatibility issue form on GitHub. Include the app/runtime
versions from About, macOS version, chip, steps, a minimal synthetic program,
expected result, and actual output or diagnostics. Remove private data. For
security concerns follow SECURITY.md.
