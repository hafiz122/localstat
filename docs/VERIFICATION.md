# Verification record

Verified on 29 October 2026 on macOS 26.4.1, Apple Silicon, using Xcode's Swift 6.3.3 and pinned Zig 0.16.0. The app declares macOS 14 as its deployment target; it has not been exercised on a macOS 14 installation.

## Automated results

| Check | Result |
| --- | --- |
| Unmodified upstream at 927a2fa9f1401e365d975536bd704819ada1f1f4 | 963 unit tests, 1,924 corpus programs, 11 end-to-end programs passed |
| Modified runtime | 966 unit tests, 1,924 corpus programs, 11 end-to-end programs passed |
| Swift integration | 6 tests passed, including actual bundled runtime execution |
| Packaged-runtime integration | 13 tests passed, including parameterized negative cases |
| Binary architecture | Both app and helper are Mach-O ARM64 |
| Bundle signature | Ad-hoc signature passes codesign --verify --deep --strict |

The modified ODS corpus fixture intentionally expects an error instead of silent destination substitution. Other upstream expectations remain unchanged.

Swift checks exercise unsaved snapshots, filenames/working directories containing spaces, relative includes, clean WORK state between runs, both large output streams, diagnostic coordinate parsing, aligned listings, launch/exit/crash classification, cancellation, and overlapping-run rejection. A ready-file handshake ensures the signal-ignoring cancellation fixture has installed its handler before cancellation; the test verifies SIGKILL after at least 1.9 seconds.

Regression checks cover analytical coefficients, standard errors and t/F probabilities, multiple predictors, scaling/pivot permutation, complete-case filtering, singular/insufficient data, constant responses, perfect fits, nonnumeric/unknown variables, syntax/unsupported options, macros and titles, explicit file persistence, ODS rejection, and CLI input failures.

The published comparison uses the public US population observations and rounded estimates from [SAS/STAT 13.2, PROC REG, Figure 85.5](https://support.sas.com/documentation/cdl/en/statug/67523/HTML/default/statug_reg_gettingstarted02.htm). Its tolerance is half the last printed decimal plus 1e-7. Analytical checks use absolute tolerances down to 1e-12 (1e-20 for scaled coefficients) and 1e-9 for parsed text results. No direct execution against an installed SAS engine was performed; no feature is labeled SAS-verified on that basis.

## App interaction checks

Verified through the packaged app:

- Open a sample by double-clicking its project row; switch between document tabs.
- Run simple regression and the DATA/macro/MEANS example; inspect actual results.
- Create a new program, edit and run unsaved source.
- Save a program whose filename contains spaces; confirm the unsaved indicator clears and the project list refreshes.
- Use native Find and Undo.
- Double-click an original-source diagnostic and verify the failing line is selected.
- Run a long calculation, click Stop, and observe Cancelled with Run enabled again.
- Close an unsaved tab and observe the save/cancel/discard prompt.
- Choose a different project directory and verify the sidebar and working-directory label.
- Export the last run through the native save dialog; compare the saved stdout/stderr exactly with a direct execution of the bundled runtime.
- Open Compatibility and Limitations in its native read-only window; close it with Command-W and verify the program remains open and runnable.
- Close the last program, verify Run is disabled and the empty-state message appears, then create a new program and verify Ready and Run are restored.
- Resize to the 760 × 540 minimum window size; verify controls, editor, output tabs, and status remain visible and the text panes scroll.

The first visual pass found collapsed split panes; that was corrected and visually rechecked. Text regression tables are padded for readability while raw exported output remains unchanged.

The resumed UI pass verified the output-tab padding and corrected a stale empty-state status. Help now displays bundled documentation inside LocalStat rather than depending on an external Markdown viewer. The final rebuild passed all six Swift integration tests again. The inspected appearance was dark/system; light appearance has not been visually exercised.

## UI review against the approved direction

The approved native AppKit direction is implemented: standard controls, system appearance, editor focus, file navigation and local run status. No fabricated metrics, decorative media, animation or marketing elements are present. All functional interactions listed above passed, including the resumed Help/Export checks and minimum-size layout. Light-appearance review remains outstanding; the record does not claim that appearance was checked.
