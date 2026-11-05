# LocalStat 0.1.1-alpha

This developer preview brings the current source editor into a downloadable
Apple Silicon build. The workspace now opens in a SAS Studio style light
appearance with an expandable local folder tree, program tabs, a code toolbar,
results, output data, and diagnostics. The interface remains LocalStat's own
AppKit implementation. System, Light, and Dark appearances remain available.

This release also includes saved editor and output settings, searchable offline
Help, formatted tables for supported PRINT, FREQ, and TABULATE output, native
table printing, and searchable PDF run reports. Program runs start fresh local
processes and use the documented SAS-language subset. The bundled OpenSAS
runtime remains pinned to the revision recorded in the repository.

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
