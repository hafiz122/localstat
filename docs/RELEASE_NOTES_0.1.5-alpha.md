# LocalStat 0.1.5-alpha

This update keeps the SAS Native editor gutter divider below the program tab
and toolbar, fixing the line that crossed the active tab name. It also carries
the 0.1.4 startup changes: a fresh workspace starts empty, bundled examples
stay separate from the Project Explorer, and the extra blue "LocalStat Studio"
bar is gone. Existing selected project folders still reopen. CI and release
packaging now use the supported macOS 15 runner.

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
