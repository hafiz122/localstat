# Verification record

## Current integration: 5 November 2026

The maintained suite includes the memory and PRINT optimizations below, plus
later editor, PDF, and benchmark-auditor regressions. Run `./scripts/test.sh`
for the current source: 973 runtime unit tests, 1,924 corpus programs, 11
end-to-end programs, 78 Swift tests (one opt-in measurement skipped by default),
16 packaged-runtime checks, 37 benchmark checks, 3 Help checks, and the
repository text check. The dated records below retain the counts and source
identity of their original runs.

## Performance optimization follow-up: 4 November 2026

The memory and PRINT changes passed 973 runtime unit tests, all 1,924 corpus
programs, and all 11 end-to-end fixtures. The Swift suite reports 57 tests with
one opt-in benchmark skip and no failures (56 regular checks passed). Packaged
runtime, Help, text-convention, and benchmark harness/report checks also pass.

The controlled study records 1,406 interleaved before/after CLI observations and
506 counterbalanced native runner/app/table-construction observations. All
observations pass their stated checks; output hashes, canonical sidecar JSON,
and table page counts match across builds. These are performance and regression
checks, not new installed-SAS validation.

See [the frozen optimization evidence](paper/results/2026-11-04-optimization/README.md)
for source/binary hashes, red/green regression records, raw measurements,
before/after summaries, and reproduction commands. The initial measurements
and original alpha verification remain separate historical records below.

## Alpha baseline

Baseline verified on 29 October 2026 on macOS 26.4.1, Apple Silicon, with Swift 6.3.3 and Zig 0.16.0. Public-alpha preparation checks were extended on 1 November 2026. Exact candidate commit, toolchains, archive hash, and fresh-run results are recorded by scripts/release-alpha.sh in dist/CANDIDATE_VERIFICATION.md and the GitHub draft release body. macOS 14 is the deployment target and CI runner; no second physical Mac has been tested.

## Automated results

| Check | Result |
| --- | --- |
| Unmodified upstream at 927a2fa9f1401e365d975536bd704819ada1f1f4 | 963 unit tests, 1,924 corpus programs, 11 end-to-end programs passed |
| Modified runtime | 968 unit tests, 1,924 corpus programs, 11 end-to-end programs passed |
| Swift candidate suite | 27 tests, including editor transformations, native AppKit workflows in both appearances, bundled runtime execution, and searchable multipage PDF generation; see candidate record for the final run |
| Packaged-runtime integration | 13 tests passed, including parameterized negative cases |
| Binary architecture | Both app and helper are Mach-O ARM64 |
| Bundle signature | Ad-hoc signature passes codesign --verify --deep --strict |
| Alpha package | Versioned ARM64 ZIP extracts cleanly; app signature, bundle version, helper version, architecture and SHA-256 generation pass |

The modified ODS corpus fixture intentionally expects an error instead of silent destination substitution. Other upstream expectations remain unchanged.

Swift checks exercise bracket pairing, selection wrapping, closing-bracket skipping, paired deletion, SAS-aware newline indentation, Tab/Shift-Tab indentation, unsaved snapshots, filenames/working directories containing spaces, relative includes, clean WORK state between runs, both large output streams, diagnostic coordinate parsing, aligned listings, report metadata, searchable multipage PDF generation, launch/exit/crash classification, cancellation, and overlapping-run rejection. A ready-file handshake ensures the signal-ignoring cancellation fixture has installed its handler before cancellation; the test verifies SIGKILL after at least 1.9 seconds.

Regression checks cover analytical coefficients, standard errors and t/F probabilities, multiple predictors, scaling/pivot permutation, complete-case filtering, singular/insufficient data, constant responses, perfect fits, nonnumeric/unknown variables, syntax/unsupported options, macros and titles, explicit file persistence, ODS rejection, and CLI input failures.

Security regression coverage rejects SAS catalog files with cyclic block chains, impossible physical page counts, and entry counts that would otherwise drive disproportionate allocation.

The published comparison uses the public US population observations and rounded estimates from [SAS/STAT 13.2, PROC REG, Figure 85.5](https://support.sas.com/documentation/cdl/en/statug/67523/HTML/default/statug_reg_gettingstarted02.htm). Its tolerance is half the last printed decimal plus 1e-7. Analytical checks use absolute tolerances down to 1e-12 (1e-20 for scaled coefficients) and 1e-9 for parsed text results. No direct execution against an installed SAS engine was performed; no feature is labeled SAS-verified on that basis.

## App interaction checks

Verified through the packaged app:

- Open a sample by double-clicking its project row; switch between document tabs.
- Run simple regression and the DATA/macro/MEANS example; inspect actual results.
- Create a new program, edit and run unsaved source.
- Save a program whose filename contains spaces; confirm the unsaved indicator clears and the project list refreshes.
- Use native Find and Undo.
- Verify Return indentation after DATA and DO statements, Return between paired brackets, Tab and Shift-Tab, selection wrapping, closing-bracket skipping, paired Backspace deletion, and Command-Z restoration.
- Double-click an original-source diagnostic and verify the failing line is selected.
- Run a long calculation, click Stop, and observe Cancelled with Run enabled again.
- Close an unsaved tab and observe the save/cancel/discard prompt.
- Choose a different project directory and verify the sidebar and working-directory label.
- Export the last run as text through the native save dialog; compare the saved stdout/stderr exactly with a direct execution of the bundled runtime.
- Export the last run as a PDF report; verify the generated document is searchable, paginated, and includes run metadata, source, output, and diagnostics.
- Open Compatibility and Limitations in its native read-only window; close it with Command-W and verify the program remains open and runnable.
- Close the last program, verify Run is disabled and the empty-state message appears, then create a new program and verify Ready and Run are restored.
- Resize to the 760 × 540 minimum window size; verify controls, editor, output tabs, and status remain visible and the text panes scroll.

The first visual pass found collapsed split panes; that was corrected and visually rechecked. Text regression tables are padded for readability while raw exported output remains unchanged.

The 1 November preparation pass visually inspected the packaged editor and results in both light and dark system appearance, and restored the original dark setting afterward. Native AppKit integration tests exercise open/edit/save, unsaved source, relative includes, diagnostics, a 5,000-line run, cancellation, and PDF generation in both appearances. Separate native editor tests verify paste preservation and bracket Undo in both appearances. Packaged File-menu PDF and text exports were exercised and produced files; PDF structure and pagination also have automated coverage.

Strings, comments, DATALINES text, and Unicode selections have focused editor regression tests. New tests first reproduced unintended bracket pairing in literal text, then passed after correction. The indentation logic remains heuristic and is not a full SAS parser.

## UI review against the approved direction

The current source direction is SAS Native by default, with a Project Explorer, active and unsaved program tabs, contextual Run controls, and SAS-like table presentation. System, Light, and Dark remain explicit choices. Historical preparation inspected both system appearances; current-source visual inspection should be recorded separately. A second physical Mac installation test remains outstanding.
