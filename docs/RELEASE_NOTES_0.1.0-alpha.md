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

The downloadable app is ARM64-only, ad-hoc signed, and not notarized. It is a
developer preview rather than a consumer-ready macOS distribution. Build from
source for the clearest trust path. See `docs/COMPATIBILITY.md` for tested
coverage and known gaps.

The Patrick Jane photographic logo is not licensed under Apache-2.0 and blocks
public redistribution unless separate permission is documented. See
`ASSET_LICENSES.md`.
