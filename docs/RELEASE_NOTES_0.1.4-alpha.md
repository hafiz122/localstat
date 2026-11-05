# LocalStat 0.1.4-alpha

On a fresh launch, SAS Native opens with an empty Project Explorer and an
untitled program. Bundled examples no longer appear in the left pane or open
automatically. Editable copies remain in
`~/Library/Application Support/LocalStat/Examples`; Help can open an example
in a new unsaved tab, and the Examples folder can be opened explicitly as a
project. An explicitly selected project folder still reopens on launch.

The extra "LocalStat Studio" bar above the workbench is removed. The Project
Explorer, program tabs, toolbar, results, and status area retain their compact
layout at the app's minimum window size. Supported PRINT, FREQ, and TABULATE
tables retain complete cell borders on screen, in print, and in PDF reports.

The app is ARM64-only, ad-hoc signed, and not notarized. It is not a complete
SAS implementation and is not affiliated with SAS Institute. Run only trusted
programs and project folders: programs have the app's file access and inherit
its environment. See `docs/INSTALL.md`, `docs/COMPATIBILITY.md`, and
`docs/VERIFICATION.md` for installation, coverage, and validation details.

The owner has confirmed permission for the Patrick Jane photographic logo;
the grant reference and attribution details remain outstanding in
`ASSET_LICENSES.md`. A second physical Mac installation test remains
outstanding. The release archive includes its SHA-256 checksum and records the
source commit and verification results.
