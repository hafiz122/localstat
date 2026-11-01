# LocalStat 0.1.0-alpha

This is the first source and developer-preview alpha of LocalStat, a native
Apple Silicon editor backed by a bundled, extended OpenSAS runtime.

The alpha is useful for evaluating the editor workflow, local whole-program
execution, text results, and the documented `PROC REG` subset. It is not a
complete SAS implementation and must not be used for clinical, regulated, or
production-critical work.

Completed runs can be saved as exact raw text or exported as searchable,
paginated PDF reports containing the executed source snapshot, run metadata,
output, and diagnostics. PDF report export is an IDE feature, not an ODS
destination.

The editor preserves and extends SAS block indentation on Return, supports
two-space Tab and Shift-Tab indentation, and pairs parentheses, square
brackets, and braces. Bracket pairing wraps selections and integrates with
native Undo.

The downloadable app is ARM64-only, ad-hoc signed, and not notarized. It is a
developer preview rather than a consumer-ready macOS distribution. Build from
source for the clearest trust path. See `docs/COMPATIBILITY.md` for tested
coverage and known gaps.

The owner has confirmed permission for the Patrick Jane photographic logo;
it remains excluded from Apache-2.0. Grant reference and attribution are still
pending in ASSET_LICENSES.md. The owner authorized public publication on
1 November 2026. A second physical Mac installation test remains outstanding.

Editor assistance now respects strings, comments, and DATALINES content.
See docs/INSTALL.md for installation, checksum verification, and known issues.
The bundle records the release version and source commit. Third-party notices
include the ReadStat-derived readers and external source test fixtures.
